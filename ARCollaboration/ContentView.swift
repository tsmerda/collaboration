//
//  ContentView.swift
//  ARCollaboration
//
//  Created by Tomáš Šmerda on 09.04.2022.
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    @StateObject var vm = ARViewModel()
    
    var body: some View {
        return ZStack {
            ARViewContainer()
                .edgesIgnoringSafeArea(.all)
                .environmentObject(vm)
            
            VStack {
                Button(action: vm.downloadSampleUSDZ) {
                    Text("Download MODEL")
                }
                .padding()
                
                Button(action: vm.removeModelsFromLocalStorage) {
                    Text("Remove MODELS")
                }
                .padding()
                
                Spacer()
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var vm: ARViewModel
    
    typealias UIViewType = ARView
    
    func makeUIView(context: Context) -> ARView {
        vm.arView.session.delegate = context.coordinator
        
        return vm.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
    }
}

extension ARView {
    // Extend ARView to implement tapGesture handler
    // Hybrid workaround between UIKit and SwiftUI
    
    func gestureSetup() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(recognizer:)))
        self.addGestureRecognizer(longPressGestureRecognizer)
    }
    
    @objc func handleLongPress(recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        
        if let entity = self.entity(at: location) {
            // Odstraneni objektu s nazvem "cake"
            if let anchorEntity = entity.anchor, entity.name == "cake" {
                anchorEntity.removeFromParent()
                print("Removed anchor with name: \(entity.name)")
            }
        }
    }
    
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        let tapLocation = recognizer.location(in: self)
        
        // Kontrola, zda interagujeme s některým AR objektem
        guard let rayResult = self.ray(through: tapLocation) else { return }
        
        // Objekt se kterým interagujeme
        let result = self.scene.raycast(origin: rayResult.origin, direction: rayResult.direction)
        
        if let firstResult = result.first {
            // Raycast intersected with AR object
            // Place object on top of existing AR object
            print("TOUCHED ENTITY NAMED! \(firstResult.entity.name)")
            
            var position = firstResult.position
            position.y += 0.01
            
            placeSceneObjectOnPosition(named: "cake", position: position)
        } else {
            // Raycast has not intersected with AR object
            // Place an object on real-world surface (if present)
            // Attempt to find a 3D location on a horizontal surface underneath the user's touch location.
            let results = self.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any)
            if let firstResult = results.first {
                // Add an ARAnchor at the touch location with a special name you check later in `session(_:didAdd:)`.
                // Vytvori ARAnchor se jmenem a transformaci a ulozi ho do Session
                let anchor = ARAnchor(name: "cake", transform: firstResult.worldTransform)
                self.session.add(anchor: anchor)
            } else {
                print("Warning: Object placement failed.")
            }
        }
    }
    
    // Umisteni entity na povrch objektu
    func placeSceneObjectOnPosition(named entityName: String, position: SIMD3<Float>){
        let entity = try! ModelEntity.loadModel(named: entityName)
        
        entity.generateCollisionShapes(recursive: true)
        self.installGestures([.all], for: entity)
        entity.name = "cake"
        
        let anchorEntity = AnchorEntity(world: position)
        // Nastavení velikosti modelu
        //        anchorEntity.scale = [0.1, 0.1, 0.1]
        anchorEntity.addChild(entity)
        self.scene.addAnchor(anchorEntity)
    }
    
    // Vkládání daného objektu do scény
    func placeSceneObject(named entityName: String, for anchor: ARAnchor){
        // let entityNameUrl = "file:///var/mobile/Containers/Data/Application/C4BD81E3-E373-4D11-B59C-11569D4A35F5/Documents/toy_drummer.usdz"
        
        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var entityNameUrl = URL(string: "")
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsUrl,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles)
            for fileURL in fileURLs {
                if fileURL.pathExtension == "usdz" {
                    entityNameUrl = fileURL
                }
            }
        } catch { print(error) }
        
        print(entityNameUrl ?? "")
        
        //    TODO: -- Kontrola zda existuje entityNameUrl
        let entity = try! ModelEntity.loadModel(contentsOf: entityNameUrl!, withName: "toy_drummer")
        
        //        let entity = try! ModelEntity.loadModel(named: entityName)
        
        entity.generateCollisionShapes(recursive: true)
        self.installGestures([.all], for: entity)
        entity.name = "cake"
        
        let anchorEntity = AnchorEntity(anchor: anchor)
        // Nastavení velikosti modelu
        //        anchorEntity.scale = [0.1, 0.1, 0.1]
        anchorEntity.addChild(entity)
        self.scene.addAnchor(anchorEntity)
    }
}

extension ARViewContainer {
    // Communicate changes from UIView to SwiftUI by updating the properties of your coordinator
    // Confrom the coordinator to ARSessionDelegate
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        // Kontrola a správa nově přidaných anchors
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let participantAnchor = anchor as? ARParticipantAnchor{
                    print("Established joint experience with a peer.")
                    
                    let anchorEntity = AnchorEntity(anchor: participantAnchor)
                    let mesh = MeshResource.generateSphere(radius: 0.03)
                    let color = UIColor.red
                    let material = SimpleMaterial(color: color, isMetallic: false)
                    let coloredSphere = ModelEntity(mesh:mesh, materials:[material])
                    
                    anchorEntity.addChild(coloredSphere)
                    
                    self.parent.vm.arView.scene.addAnchor(anchorEntity)
                } else {
                    // Kontrola, zda má anchor požadovaný název modelu
                    if let anchorName = anchor.name, anchorName == "cake" {
                        //                        print("DIDADD \(anchor)")
                        self.parent.vm.arView.placeSceneObject(named: anchorName, for: anchor)
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
            guard let multipeerSession = self.parent.vm.multipeerSession else { return }
            if !multipeerSession.connectedPeers.isEmpty {
                guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
                else { fatalError("Unexpectedly failed to encode collaboration data.") }
                // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
                let dataIsCritical = data.priority == .critical
                multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
            }
            //            else {
            //                print("Deferred sending collaboration to later because there are no peers.")
            //            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}

#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

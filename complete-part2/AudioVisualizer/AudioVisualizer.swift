//
//  AudioVisualizer.swift
//  AudioVisualizer
//
//  Created by Alex Barbulescu on 2019-04-06.
//  Copyright © 2019 alex. All rights reserved.
//

import Cocoa
import MetalKit
import simd

let resolution = TimeInterval(1.0 / 120)
let freqeuencyBufferLength = 362 * MemoryLayout<Float>.stride
class AudioVisualizer: NSView {
    
    //MARK: METAL VARS
    private var metalView : MTKView!
    private var metalDevice : MTLDevice!
    private var metalCommandQueue : MTLCommandQueue!
    private var metalRenderPipelineState : MTLRenderPipelineState!
    
    //MARK: VERTEX VARS
    private var circleVertices = [simd_float2]()
    private var vertexBuffer : MTLBuffer!
    
    private var loudnessUniformBuffer : MTLBuffer!
    public var loudnessMagnitude : Float = 0.3 {
        didSet{
            loudnessUniformBuffer.contents().copyMemory(from: &loudnessMagnitude, byteCount: MemoryLayout<Float>.stride)
        }
    }
    
    private var freqeuencyBuffer : MTLBuffer!
    public var frequencyVertices : [Float] = [Float](repeating: 0, count: 361) {
        didSet{
            let sliced = Array(frequencyVertices[76..<438])
            freqeuencyBuffer.contents().copyMemory(from: sliced,
                                                   byteCount: freqeuencyBufferLength)
            renderDraw()
        }
    }

    //MARK: INIT
    public required init() {
        super.init(frame: .zero)
        setupView()
        createVertexPoints()
        setupMetal()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    //MARK: SETUP
    fileprivate func setupView(){
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    var lastDraw = Date().timeIntervalSince1970
    let drawSemaphore = DispatchSemaphore(value: 1)
    let renderQueue = DispatchQueue(label: "Render Queue", qos: .userInteractive)
    
    @objc
    func _draw() {
        let current = Date().timeIntervalSince1970
        if lastDraw + resolution > current {
            return
        }
        lastDraw = current
        metalView.draw()
    }
    
    func renderDraw() {
        performSelector(inBackground: #selector(_draw), with: nil)
    }
    
    fileprivate func setupMetal(){
        //view
        metalView = MTKView()
        addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        metalView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        metalView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        metalView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        
        metalView.delegate = self
        
        //updates
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        
        //connect to the gpu
        metalDevice = MTLCreateSystemDefaultDevice()!
        metalView.device = metalDevice
        
        //creating the command queue
        metalCommandQueue = metalDevice.makeCommandQueue()!
        
        //creating the render pipeline state
        createPipelineState()
        
        //turn the vertex points into buffer data
        vertexBuffer = metalDevice.makeBuffer(bytes: circleVertices, length: circleVertices.count * MemoryLayout<simd_float2>.stride, options: [])!
        
        //initialize the loudnessUniform buffer data
        loudnessUniformBuffer = metalDevice.makeBuffer(bytes: &loudnessMagnitude, length: MemoryLayout<Float>.stride, options: [])!
        
        //initialize the freqeuencyBuffer data
        freqeuencyBuffer = metalDevice.makeBuffer(bytes: frequencyVertices, length: frequencyVertices.count * MemoryLayout<Float>.stride, options: [])!
        
        loudnessUniformBuffer = metalDevice.makeBuffer(bytes: &loudnessMagnitude, length: MemoryLayout<Float>.stride, options: [])!
        
        freqeuencyBuffer = metalDevice.makeBuffer(length: freqeuencyBufferLength)
        
        //draw
        renderDraw()
    }
    
    fileprivate func createPipelineState(){
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        
        //finds the metal file from the main bundle
        let library = metalDevice.makeDefaultLibrary()!
        
        //give the names of the function to the pipelineDescriptor
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")

        //set the pixel format to match the MetalView's pixel format
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        
        //make the pipelinestate using the gpu interface and the pipelineDescriptor
        metalRenderPipelineState = try! metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    fileprivate func createVertexPoints(){
        func rads(forDegree d: Float)->Float32{
            return (Float.pi*d)/180
        }
        
        let origin = simd_float2(0, 0)
        
        for i in 0...720 {
            let position : simd_float2 = [cos(rads(forDegree: Float(Float(i)/2.0))),sin(rads(forDegree: Float(Float(i)/2.0)))]
            circleVertices.append(position)
            if (i+1)%2 == 0 {
                circleVertices.append(origin)
            }
        }
    }
    
}

extension AudioVisualizer : MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        //not worried about this
    }
    
    func draw(in view: MTKView) {
        //Creating the commandBuffer for the queue
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer(),
        let vertexBuffer = vertexBuffer,
        let loudnessUniformBuffer = loudnessUniformBuffer,
        let freqeuencyBuffer = freqeuencyBuffer,
        let currentDrawable = view.currentDrawable else {return}
        //Creating the interface for the pipeline
        guard let renderDescriptor = view.currentRenderPassDescriptor else {return}
        //Setting a "background color"
        renderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        
        //Creating the command encoder, or the "inside" of the pipeline
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {return}
        
        // We tell it what render pipeline to use
        renderEncoder.setRenderPipelineState(metalRenderPipelineState)
        
        /*********** Encoding the commands **************/
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(loudnessUniformBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(freqeuencyBuffer, offset: 0, index: 2)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 1081)
        renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 1081, vertexCount: 1081)
        
        renderEncoder.endEncoding()
        commandBuffer.present(currentDrawable)
        
        commandBuffer.addCompletedHandler {[weak self] _ in
            self?.drawSemaphore.signal()
        }
        commandBuffer.commit()
    }
}

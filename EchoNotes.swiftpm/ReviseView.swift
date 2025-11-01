//

import SwiftUI
import PencilKit
import AVFoundation
import Speech
@preconcurrency import Vision

struct ReviseView: View {
    
    @State private var drawings: [PKDrawing] = [PKDrawing()]
    @State private var isSummaryMode  = false      // false ⇒ Notes, true ⇒ Summary
    @State private var isSummarizing  = false
    @State private var summaryText    = ""
    
    @StateObject private var transcriber = SpeechTranscriber()
    
    @State var isPresentedSummeary : Bool
    @State var isPresentedNotes = false
    @State var isPresentedRevise : Bool
    
    var body: some View {
        NavigationStack{
            GeometryReader { geo in
                
                
                VStack(alignment: .center,spacing: 0) {
                    
                    // Top toggle bar
                    HStack(spacing: 12) {
                        Spacer()
                        Button {
                            isPresentedNotes = true          // ← Notes
                        } label: {
                            Label("Notes", systemImage: "book.pages")
                                .frame(width: 115, height: 45)
                                .background(.white)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                        }
                        .fullScreenCover(isPresented: $isPresentedNotes) {
                            ContentView(isPresentedNotes: isPresentedNotes)
                        }
                        
                        Button {
                            isPresentedSummeary = true// ← Summary
                        } label: {
                            Label("Summary", systemImage: "sparkles")
                                .frame(width: 115, height: 45)
                                .background(.white)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                        }
                        .fullScreenCover(isPresented: $isPresentedSummeary) {
                            SummaryView(isPresentedSummeary: isPresentedSummeary)
                        }
                        Button {
                            isPresentedRevise = true
                        } label: {
                            Label("Revise", systemImage: "wand.and.rays.inverse")
                                .frame(width: 115, height: 45)
                                .background(Color(hex: "013951"))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .fullScreenCover(isPresented: $isPresentedSummeary) {
                            SummaryView(isPresentedSummeary: isPresentedSummeary)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                    HStack{
                        Spacer()
                        NavigationLink {
                            //ParagraphView(isPresentedSummeary: false)
                            
                        } label: {
                            HStack {
                                Image(systemName: "menucard")
                                Text("Flashcards")
                            }
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .frame(width: 230, height: 200)
                            .background(Color(hex: "013951")) // background ตรง HStack
                            .cornerRadius(10) // ถ้าอยากให้ขอบโค้งนิดนึง
                            .padding()
                        }
                        
                        
                        NavigationLink {
                            //ParagraphView(isPresentedSummeary: false)
                            
                        } label: {
                            HStack {
                                Image(systemName: "questionmark.text.page")
                                Text("Quiz")
                            }
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .frame(width: 230, height: 200)
                            .background(Color(hex: "013951")) // background ตรง HStack
                            .cornerRadius(10) // ถ้าอยากให้ขอบโค้งนิดนึง
                            .padding()
                        }
                        
                        NavigationLink {
                            //ParagraphView(isPresentedSummeary: false)
                            
                        } label: {
                            HStack {
                                Image(systemName: "ellipsis.circle")
                                Text("Other")
                            }
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .frame(width: 230, height: 200)
                            .background(Color(hex: "013951")) // background ตรง HStack
                            .cornerRadius(10) // ถ้าอยากให้ขอบโค้งนิดนึง
                            .padding()
                        }
                        Spacer()
                        
                    }
                    Spacer()
                }
                
                
                
                
                
                
            }
            .background(Color(.systemGray5))
        }
    }
    
    // MARK: – Generate summary (all pages)
    func generateSummary() {
        Task {
            isSummarizing = true
            summaryText   = ""
            
            do {
                // 🖋️ OCR every page in parallel
                let ocrPages = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
                    for drawing in drawings {
                        group.addTask { try await performOCR(from: drawing) }
                    }
                    return try await group.reduce(into: []) { $0.append($1) }
                }
                let combinedNotes = ocrPages.joined(separator: "\n\n")
                
                // 🧠 call LLM for a concise summary
                let prompt = """
                สรุปเนื้อหาด้านล่างให้กระชับ ชัดเจน เป็นข้อ ๆ (ภาษาไทย):
                
                📝 โน้ตจากลายมือ:
                \(combinedNotes)
                
                🎙️ ถอดความเสียง:
                \(transcriber.transcript)
                """
                
                summaryText = try await sendToTogetherAI(
                    handwritten: combinedNotes,
                    transcript : prompt   // we’ll ignore transcript param inside…
                )
                
            } catch {
                summaryText = "Error: \(error.localizedDescription)"
            }
            
            isSummarizing = false
        }
    }
    
    // MARK: - Modern Vision handwriting OCR (iOS 17+)
    @available(iOS 17.0, *)
    func performOCR(from drawing: PKDrawing) async throws -> String {
        
        // 1. Compute the drawing’s bounding box and add padding
        var bbox = drawing.bounds
        bbox = bbox.insetBy(dx: -20, dy: -20)
        if bbox.isEmpty {          // nothing drawn yet → use a default canvas
            bbox = CGRect(origin: .zero, size: .init(width: 512, height: 512))
        }
        
        // 2. Render the drawing at higher DPI so Vision “sees” thin strokes
        let renderScale: CGFloat = 3.0         // 👈 try 4.0 if strokes are extremely fine
        let rendered = drawing.image(from: bbox, scale: renderScale)
        guard let cgImage = rendered.cgImage else {
            throw NSError(domain: "OCR", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn’t create CGImage from PKDrawing"])
        }
        
        // 3. Configure the request – Vision automatically detects handwriting & language
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel             = .accurate
        textRequest.usesLanguageCorrection       = true
        textRequest.automaticallyDetectsLanguage = true            // 🔑 iOS 17 handwriting pipeline
        textRequest.minimumTextHeight            = 0.01            // help Vision accept small text
        
        // 4. Run the request in a continuation so we can ‘await’ the result
        return try await withCheckedThrowingContinuation { cont in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([textRequest])
                    let observations = textRequest.results ?? []
                    
                    let result = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
    
    
    struct ChatCompletionRequest: Encodable {
        
        struct Message: Encodable {
            
            let role: String
            
            let content: String
            
        }
        
        
        
        let model: String
        
        let messages: [Message]
        
    }
    
    
    
    struct ChatCompletionResponse: Decodable {
        
        struct Choice: Decodable {
            
            struct Message: Decodable {
                
                let role: String
                
                let content: String
                
            }
            
            let message: Message
            
        }
        
        let choices: [Choice]
        
    }
    
    
    
    func sendToTogetherAI(handwritten: String, transcript: String) async throws -> String {
        
        // Replace with your actual Together.ai key
        
        let apiKey = "1c9d354e4e20299d8dc7567cb4a73fcd31f615b257f31c54ec138dd01d58e2c1"
        
        let url = URL(string: "https://api.together.ai/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        
        
        // Build up the prompt
        
        let systemPrompt = ChatCompletionRequest.Message(
            
            role: "system",
            
            content: "You are an assistant that compares handwritten notes to an audio transcript and returns only the points or mentioned in the transcript but missing from the notes."
            
        )
        
        
        
        let userPromptText = """
    
    Here are the handwritten notes (in Thai):
    
    
    
    \(handwritten)
    
    
    
    Here is the audio transcript (in Thai):
    
    
    
    \(transcript)
    
    
    
    Please list everything that appeared in the transcript but is NOT present in the handwritten notes. I also want you to tell me what did you get from the handwritten notes
    
    """
        
        
        
        let userPrompt = ChatCompletionRequest.Message(role: "user", content: userPromptText)
        
        
        
        let body = ChatCompletionRequest(
            
            model: "scb10x/scb10x-llama3-1-typhoon2-8b-instruct",
            
            messages: [systemPrompt, userPrompt]
            
        )
        
        
        
        request.httpBody = try JSONEncoder().encode(body)
        
        
        
        // Send the request
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            
            throw URLError(.badServerResponse)
            
        }
        
        
        
        // Decode and return the assistant's reply
        
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        return chatResponse.choices.first?.message.content
        
        ?? "ได้รับคำตอบแต่ไม่พบเนื้อหาในฟิลด์ที่คาดไว้"
        
        
    }
}

#Preview {
    ReviseView(isPresentedSummeary: false, isPresentedRevise: false)
}




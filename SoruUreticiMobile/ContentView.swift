import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import UIKit
import SwiftLlama
import ZIPFoundation

enum QuestionMode: String, CaseIterable, Identifiable {
    case test = "Test"
    case classic = "Klasik"

    var id: String { rawValue }

    var modelType: String {
        switch self {
        case .test:
            return "çoktan seçmeli"
        case .classic:
            return "açık uçlu"
        }
    }
}

struct GeneratedQuestion: Identifiable {
    let id = UUID()
    let type: String
    let question: String
    let options: [String]
    let answer: String
}

struct ModelQuestion: Decodable {
    let type: String?
    let question: String?
    let options: [String]?
    let answer: String?
    enum CodingKeys: String, CodingKey {
        case type
        case question
        case options
        case answer
        case soru
        case cevap
        case secenekler
        case seçenekler
    }
    init(type: String?, question: String?, options: [String]?, answer: String?) {
        self.type = type
        self.question = question
        self.options = options
        self.answer = answer
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.type = try container.decodeIfPresent(String.self, forKey: .type)

        self.question =
            try container.decodeIfPresent(String.self, forKey: .question)
            ?? container.decodeIfPresent(String.self, forKey: .soru)

        self.options =
            try container.decodeIfPresent([String].self, forKey: .options)
            ?? container.decodeIfPresent([String].self, forKey: .secenekler)
            ?? container.decodeIfPresent([String].self, forKey: .seçenekler)
        
        self.answer =
            try container.decodeIfPresent(String.self, forKey: .answer)
            ?? container.decodeIfPresent(String.self, forKey: .cevap)
    }
}

struct ContentView: View {
    @State private var selectedFileName: String = "Dosya seçilmedi"
    @State private var extractedText: String = ""
    @State private var generatedQuestions: [GeneratedQuestion] = []

    @State private var questionCount: Int = 5
    @State private var selectedMode: QuestionMode = .test

    @State private var isFileImporterPresented = false
    @State private var isGenerating = false
    @State private var statusMessage = ""
    @State private var createdPDFURL: URL?
    @State private var isShareSheetPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {

                    fileSection

                    settingsSection

                    generateButton
                    
                    pdfButton

                    statusSection

                    questionsSection
                }
                .padding()
            }
            .navigationTitle("QuizMint")
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [
                    .pdf,
                    .plainText,
                    UTType(filenameExtension: "docx") ?? .data
                ],
                allowsMultipleSelection: false
            ){ result in
                handleFileImport(result)
            }
            .sheet(isPresented: $isShareSheetPresented) {
                if let createdPDFURL {
                    ShareSheet(activityItems: [createdPDFURL])
                }
            }
        }
    }
    private var pdfButton: some View {
        Button("Sınav PDF'i Oluştur") {
            createExamPDF()
        }
        .buttonStyle(.bordered)
        .disabled(generatedQuestions.isEmpty)
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Ders Notu Dosyası")
                .font(.headline)

            Button("PDF / Word / TXT Dosyası Seç") {
                isFileImporterPresented = true
            }
            .buttonStyle(.borderedProminent)

            Text(selectedFileName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !extractedText.isEmpty {
                DisclosureGroup("") {
                    Text(extractedText)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Soru Ayarları")
                .font(.headline)

            Stepper("Soru Sayısı: \(questionCount)", value: $questionCount, in: 1...10)

            Picker("Soru Tipi", selection: $selectedMode) {
                ForEach(QuestionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var generateButton: some View {
        Button(isGenerating ? "Üretiliyor..." : "Soruları Üret") {
            Task {
                await generateQuestions()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
    }

    private var statusSection: some View {
        Group {
            if isGenerating {
                ProgressView(statusMessage)
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !generatedQuestions.isEmpty {
                Text("Üretilen Sorular")
                    .font(.headline)
            }

            ForEach(Array(generatedQuestions.enumerated()), id: \.element.id) { index, item in
                questionCard(index: index + 1, item: item)
            }
        }
    }

    private func questionCard(index: Int, item: GeneratedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index). Soru")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(removeAnswerFromQuestion(item.question))
                .font(.headline)

            if item.type.contains("açık") {
                Text(answerLines(count: 3))
                    .font(.body)
                    .padding(.top, 8)
            }

            if !item.options.isEmpty {
                ForEach(Array(item.options.enumerated()), id: \.offset) { optionIndex, option in
                    Text("\(optionLetter(for: optionIndex))) \(option)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
private func optionLetter(for index: Int) -> String {
    let letters = ["A", "B", "C", "D"]
    return index < letters.count ? letters[index] : ""
}
private func answerLines(count: Int = 4) -> String {
    Array(repeating: "____________________________________", count: count)
        .joined(separator: "\n\n")
}
extension ContentView {
    
    func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else {
                statusMessage = "Dosya seçilmedi."
                return
            }

            selectedFileName = selectedURL.lastPathComponent

            let canAccess = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            let text = try extractText(from: selectedURL)

            extractedText = text
            generatedQuestions = []
            statusMessage = "Metin başarıyla çıkarıldı."

        } catch {
            statusMessage = "Dosya okunamadı: \(error.localizedDescription)"
        }
    }

    func extractText(from url: URL) throws -> String {
        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "pdf":
            return try extractTextFromPDF(url)

        case "txt":
            return try extractTextFromTXT(url)

        case "docx":
            return try extractTextFromDOCX(url)

        default:
            throw NSError(
                domain: "UnsupportedFile",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bu dosya türü desteklenmiyor."]
            )
        }
    }

    func extractTextFromTXT(_ url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    func extractTextFromPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw NSError(
                domain: "PDFError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PDF açılamadı."]
            )
        }

        var text = ""

        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex),
               let pageText = page.string {
                text += pageText + "\n"
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractTextFromDOCX(_ url: URL) throws -> String {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NSError(
                domain: "DOCXError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "DOCX arşivi açılamadı."]
            )
        }

        guard let entry = archive["word/document.xml"] else {
            throw NSError(
                domain: "DOCXError",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "DOCX içeriği bulunamadı."]
            )
        }

        var xmlData = Data()

        _ = try archive.extract(entry) { data in
            xmlData.append(data)
        }

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw NSError(
                domain: "DOCXError",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "DOCX metni okunamadı."]
            )
        }

        return cleanDOCXXML(xmlString)
    }

    func cleanDOCXXML(_ xml: String) -> String {
        var text = xml

        text = text.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "</w:t>", with: " ")

        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
extension ContentView {

    func generateQuestions() async {
        await MainActor.run {
            isGenerating = true
            generatedQuestions = []
            statusMessage = "Model yükleniyor..."
        }

        do {
            guard let modelURL = Bundle.main.url(
                forResource: "soru_model_q4_k_m",
                withExtension: "gguf"
            ) else {
                await MainActor.run {
                    statusMessage = "Model dosyası bulunamadı."
                    isGenerating = false
                }
                return
            }

            let config = LlamaConfig(
                batchSize: 512,
                maxTokenCount: 2048,
                useGPU: true
            )

            let service = LlamaService(
                modelUrl: modelURL,
                config: config
            )

            let limitedText = limitText(extractedText, maxCharacters: 8000)

            for index in 1...questionCount {
                await MainActor.run {
                    statusMessage = "\(index). soru üretiliyor..."
                }

                let question = try await generateSingleQuestion(
                    service: service,
                    lessonText: limitedText,
                    mode: selectedMode,
                    index: index
                )

                await MainActor.run {
                    generatedQuestions.append(question)
                }
            }

            await MainActor.run {
                statusMessage = "Sorular üretildi."
                isGenerating = false
            }

        } catch {
            await MainActor.run {
                statusMessage = "Hata: \(error.localizedDescription)"
                isGenerating = false
            }
        }
    }

    func generateSingleQuestion(
        service: LlamaService,
        lessonText: String,
        mode: QuestionMode,
        index: Int
    ) async throws -> GeneratedQuestion {

        let chunks = splitTextIntoChunks(lessonText, chunkSize: 1200)
        let selectedChunk = chunks[(index - 1) % chunks.count]

        let systemMessage = LlamaChatMessage(
            role: .system,
            content: """
            Sen Türkçe ders notlarından sınav sorusu üreten bir asistansın.
            Görevin metni özetlemek değil, metinden anlamlı,mantıklı ve gerçek sınav sorusu üretmektir.
            Cevabı yalnızca geçerli JSON olarak ver.
            """
        )
        func generateClassicAnswer(
            service: LlamaService,
            lessonText: String,
            question: String
        ) async throws -> String {

            let systemMessage = LlamaChatMessage(
                role: .system,
                content: """
                Sen Türkçe ders notlarına göre kısa cevap anahtarı hazırlayan bir eğitim asistanısın.
                Sadece verilen ders notundaki bilgileri kullan.
                Bilgi ders notunda yoksa uydurma.
                """
            )

            let userMessage = LlamaChatMessage(
                role: .user,
                content: """
                Aşağıdaki ders notuna göre verilen klasik sorunun kısa ve doğru cevabını yaz.

                Kurallar:
                - Sadece cevabı yaz.
                - Soru yazma.
                - Açıklama ekleme.
                - Çok uzun yazma.
                - En fazla 2 cümle yaz.
                - Ders notunda olmayan bilgi ekleme.

                Ders notu:
                \(lessonText)

                Soru:
                \(question)
                """
            )
            

            let samplingConfig = LlamaSamplingConfig(
                temperature: 0.0,
                seed: 9000
            )

            let result = try await service.respond(
                to: [systemMessage, userMessage],
                samplingConfig: samplingConfig
            )

            return cleanClassicAnswer(result)
        }

        let userPrompt: String

        if mode == .test {
            userPrompt = """
            Aşağıdaki ders notundan 1 tane çoktan seçmeli sınav sorusu üret.

            Kesin kurallar:
            - Ders notunu aynen yazma.
            - Metni parçalara bölme.
            - Soru cümlesi üret.
            - Soru mutlaka "?" ile bitsin.
            - 4 seçenek üret.
            - Seçenekler kısa ve anlamlı olsun.
            - JSON dışında açıklama yazma.
            - Doğru cevabın harfini answer alanına yaz. Sadece A, B, C veya D yaz.
            
            Çıktı formatı birebir şöyle olmalı:
            {
              "type": "çoktan seçmeli",
              "question": "Buraya soru yaz?",
              "options": ["A seçeneği", "B seçeneği", "C seçeneği", "D seçeneği"],
              "answer": "A"
            }
            Ders notu:
            \(selectedChunk)
            """
        } else {
            userPrompt = """
            Aşağıdaki ders notundan yalnızca 1 tane klasik açık uçlu sınav sorusu üret.

            Kesin kurallar:
            - Çoktan seçmeli soru üretme.
            - Şık üretme.
            - A, B, C, D seçeneği yazma.
            - Sadece soru cümlesi üret.
            - Ders notunu aynen kopyalama.
            - JSON dışında hiçbir şey yazma.
            - answer alanına bu sorunun kısa ve doğru cevabını yaz.
            
            Çıktı formatı birebir şöyle olmalı:
            {
              "type": "açık uçlu",
              "question": "Buraya klasik açık uçlu soru yaz?",
              "options": [],
              "answer": "Bu sorunun kısa ve doğru cevabı buraya yazılacak."
            }

            Ders notu:
            \(selectedChunk)
            """
        }

        let userMessage = LlamaChatMessage(
            role: .user,
            content: userPrompt
        )

        let samplingConfig = LlamaSamplingConfig(
            temperature: 0.2,
            seed: UInt32(1000 + index)
        )

        let result = try await service.respond(
            to: [systemMessage, userMessage],
            samplingConfig: samplingConfig
        )

        let parsed = try parseQuestion(from: result)

        let rawQuestionText = parsed.question?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let parsedQuestionText = removeAnswerFromQuestion(rawQuestionText)

        let parsedOptions = parsed.options ?? []

        let parsedAnswer = parsed.answer?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let finalAnswer: String

        if mode == .classic {
            finalAnswer = try await generateClassicAnswer(
                service: service,
                lessonText: selectedChunk,
                question: parsedQuestionText
            )
        } else {
            finalAnswer = parsedAnswer
        }

        let finalQuestion = GeneratedQuestion(
            type: parsed.type ?? mode.modelType,
            question: parsedQuestionText,
            options: parsedOptions,
            answer: finalAnswer
        )

        guard isValidGeneratedQuestion(finalQuestion, mode: mode, sourceText: selectedChunk) else {
            if mode == .classic {
                return GeneratedQuestion(
                    type: "açık uçlu",
                    question: cleanClassicQuestion(from: result),
                    options: [],
                    answer: ""
                )
            }

            throw NSError(
                domain: "InvalidQuestion",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Model gerçek test sorusu üretemedi."
                ]
            )
        }

        return finalQuestion
    }
    func cleanClassicQuestion(from text: String) -> String {
        var cleaned = cleanModelOutput(text)

        cleaned = cleaned.replacingOccurrences(
            of: #""type"\s*:\s*"[^"]*""#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #""options"\s*:\s*\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"[{}\[\],"]"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(of: "question:", with: "")
        cleaned = cleaned.replacingOccurrences(of: "soru:", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Soru:", with: "")

        let forbidden = ["A)", "B)", "C)", "D)", "A.", "B.", "C.", "D."]

        for item in forbidden {
            if let range = cleaned.range(of: item) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleaned.contains("?") {
            cleaned += "?"
        }

        return cleaned
    }
    func cleanClassicAnswer(_ text: String) -> String {
        var cleaned = cleanModelOutput(text)

        cleaned = cleaned.replacingOccurrences(of: "Cevap:", with: "")
        cleaned = cleaned.replacingOccurrences(of: "cevap:", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Answer:", with: "")
        cleaned = cleaned.replacingOccurrences(of: "answer:", with: "")

        cleaned = cleaned.replacingOccurrences(
            of: #"[{}\[\]"]"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
    func removeAnswerFromQuestion(_ text: String) -> String {
        var cleaned = text

        let keywords = [
            "answer:",
            "Answer:",
            "ANSWER:",
            "cevap:",
            "Cevap:",
            "CEVAP:"
        ]

        for keyword in keywords {
            if let range = cleaned.range(of: keyword) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
    func splitTextIntoChunks(_ text: String, chunkSize: Int) -> [String] {
        let cleanText = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            return []
        }

        var chunks: [String] = []
        var currentIndex = cleanText.startIndex

        while currentIndex < cleanText.endIndex {
            let endIndex = cleanText.index(
                currentIndex,
                offsetBy: chunkSize,
                limitedBy: cleanText.endIndex
            ) ?? cleanText.endIndex

            let chunk = String(cleanText[currentIndex..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !chunk.isEmpty {
                chunks.append(chunk)
            }

            currentIndex = endIndex
        }

        return chunks
    }

    func isValidGeneratedQuestion(
        _ item: GeneratedQuestion,
        mode: QuestionMode,
        sourceText: String
    ) -> Bool {

        let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)

        if question.isEmpty {
            return false
        }

        if question.count < 15 {
            return false
        }

        if question.count > 300 {
            return false
        }

        if !question.contains("?") {
            return false
        }

        if sourceText.contains(question) {
            return false
        }

        if mode == .test {
            if item.options.count != 4 {
                return false
            }

            for option in item.options {
                let cleanOption = option.trimmingCharacters(in: .whitespacesAndNewlines)

                if cleanOption.isEmpty {
                    return false
                }

                if cleanOption.count > 150 {
                    return false
                }
            }
        }

        if mode == .classic {
            if !item.options.isEmpty {
                return false
            }

            let forbidden = ["A)", "B)", "C)", "D)", "A.", "B.", "C.", "D."]

            for word in forbidden {
                if question.contains(word) {
                    return false
                }
            }
        }

        return true
    }
    func parseQuestion(from text: String) throws -> ModelQuestion {
        guard let jsonText = extractJSON(from: text) else {
            throw NSError(
                domain: "JSONParse",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model çıktısında JSON bulunamadı."]
            )
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw NSError(
                domain: "JSONParse",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "JSON veriye çevrilemedi."]
            )
        }

        return try JSONDecoder().decode(ModelQuestion.self, from: data)
    }

   

    func cleanModelOutput(_ text: String) -> String {
        var cleaned = text

        cleaned = cleaned.replacingOccurrences(of: "<|im_start|>assistant", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|im_end|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|im_start|>", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
   
    func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var endIndex: String.Index?

        var index = start

        while index < text.endIndex {
            let char = text[index]

            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1

                if depth == 0 {
                    endIndex = index
                    break
                }
            }

            index = text.index(after: index)
        }

        guard let endIndex else {
            return nil
        }

        return String(text[start...endIndex])
    }

    func limitText(_ text: String, maxCharacters: Int) -> String {
        if text.count <= maxCharacters {
            return text
        }

        return String(text.prefix(maxCharacters))
    }
}
extension ContentView {

    func createExamPDF() {
        guard !generatedQuestions.isEmpty else {
            statusMessage = "PDF oluşturmak için önce soru üretmelisin."
            return
        }

        let pdfMetaData = [
            kCGPDFContextCreator: "Soru Üretici",
            kCGPDFContextAuthor: "Soru Üretici"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth = 595.2
        let pageHeight = 841.8
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let fileName = "sinav_kagidi.pdf"
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let pdfURL = documentsURL.appendingPathComponent(fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        do {
            try renderer.writePDF(to: pdfURL) { context in
                context.beginPage()

                var y: CGFloat = 40
                let leftMargin: CGFloat = 40
                let rightMargin: CGFloat = 40
                let contentWidth = pageWidth - leftMargin - rightMargin

                y = drawPDFText(
                    "SINAV KAĞIDI",
                    x: leftMargin,
                    y: y,
                    width: contentWidth,
                    font: .boldSystemFont(ofSize: 22),
                    alignment: .center
                )

                y += 25

                y = drawPDFText(
                    "Ad Soyad: ________________________________",
                    x: leftMargin,
                    y: y,
                    width: contentWidth,
                    font: .systemFont(ofSize: 13),
                    alignment: .left
                )

                y += 8

                y = drawPDFText(
                    "Numara: __________________   Tarih: ____ / ____ / ______",
                    x: leftMargin,
                    y: y,
                    width: contentWidth,
                    font: .systemFont(ofSize: 13),
                    alignment: .left
                )

                y += 25

                for (index, item) in generatedQuestions.enumerated() {
                    if y > pageHeight - 120 {
                        context.beginPage()
                        y = 40
                    }

                    let questionText = "\(index + 1). \(removeAnswerFromQuestion(item.question))"

                    y = drawPDFText(
                        questionText,
                        x: leftMargin,
                        y: y,
                        width: contentWidth,
                        font: .boldSystemFont(ofSize: 13),
                        alignment: .left
                    )

                    y += 8

                    if !item.options.isEmpty {
                        for (optionIndex, option) in item.options.enumerated() {
                            if y > pageHeight - 80 {
                                context.beginPage()
                                y = 40
                            }

                            let optionText = "\(optionLetter(for: optionIndex))) \(option)"

                            y = drawPDFText(
                                optionText,
                                x: leftMargin + 15,
                                y: y,
                                width: contentWidth - 15,
                                font: .systemFont(ofSize: 12),
                                alignment: .left
                            )

                            y += 4
                        }
                    } else {
                        for _ in 0..<4 {
                            if y > pageHeight - 80 {
                                context.beginPage()
                                y = 40
                            }

                            y = drawPDFText(
                                "_______________________________________________",
                                x: leftMargin + 15,
                                y: y,
                                width: contentWidth - 15,
                                font: .systemFont(ofSize: 12),
                                alignment: .left
                            )

                            y += 16
                        }
                    }

                    y += 18
                }
            }

            createdPDFURL = pdfURL
            isShareSheetPresented = true
            statusMessage = "Sınav PDF'i oluşturuldu."

        } catch {
            statusMessage = "PDF oluşturulamadı: \(error.localizedDescription)"
        }
    }
    func drawPDFText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: UIFont,
        alignment: NSTextAlignment
    ) -> CGFloat {

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(
            string: text,
            attributes: attributes
        )

        let rect = CGRect(
            x: x,
            y: y,
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )

        let calculatedRect = attributedText.boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        attributedText.draw(in: CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: ceil(calculatedRect.height)
        ))

        return y + ceil(calculatedRect.height)
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        
    }
}

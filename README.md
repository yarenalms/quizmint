<p align="center">
  <img src="docs/icon.png" width="140" alt="QuizMint uygulama ikonu">
</p>

# QuizMint — Ders Notlarından Yapay Zekâ ile Sınav Sorusu Üreten iOS Uygulaması

**QuizMint**, PDF, Word veya TXT formatındaki ders notlarından otomatik olarak çoktan seçmeli ve klasik sınav soruları üreten bir iOS uygulamasıdır. Soruları, bu proje için özel veri setiyle **fine-tune edilmiş bir dil modeli** üretir. Model **tamamen cihaz üzerinde (on-device)** çalışır: internet bağlantısı, API anahtarı ya da sunucu gerekmez, ders notları telefondan hiç çıkmaz.

> **TÜBİTAK 2209-A** Üniversite Öğrencileri Araştırma Projeleri Destekleme Programı kapsamında desteklenen proje.

## Özellikler

- **Dosyadan metin çıkarma:** PDF (PDFKit), DOCX (ZIP + XML ayrıştırma) ve TXT
- **İki soru tipi:** Test (4 şıklı, doğru cevap harfiyle) ve Klasik (açık uçlu, kısa cevap anahtarıyla)
- **Ayarlanabilir soru sayısı:** 1–10 arası
- **Sınav kâğıdı PDF'i:** Ad-soyad, numara ve tarih alanlı, çok sayfalı, paylaşılabilir A4 PDF
- **Gizlilik:** Model yerel olarak çalıştığı için hiçbir veri dışarı gönderilmez

## Nasıl Çalışır?

```
Ders notu (PDF / DOCX / TXT)
        │
        ▼
Metin çıkarma ──► Temizleme ──► 1200 karakterlik parçalara bölme
                                        │
                     her soru için farklı bir parça seçilir
                                        ▼
            Fine-tune edilmiş model (llama.cpp, GGUF, GPU hızlandırmalı)
                                        │  JSON çıktı
                                        ▼
            JSON ayrıştırma ──► Doğrulama ──► Soru kartı ──► Sınav PDF'i
```

1. **Parçalama (chunking):** Modelin bağlam penceresi sınırlı olduğu için metin 1200 karakterlik parçalara bölünür. Her soru farklı bir parçadan üretilir, böylece sorular notun farklı bölümlerine yayılır.
2. **Yapılandırılmış çıktı:** Model, cevabını `type`, `question`, `options`, `answer` alanlarını içeren JSON olarak verir. Türkçe alan adları (`soru`, `cevap`, `seçenekler`) da tolere edilir.
3. **Doğrulama katmanı:** Küçük modeller her zaman kurallara uymaz. Bu yüzden her çıktı kontrol edilir. Kontrol edilenler: soru uzunluğu (15–300 karakter), soru işareti, test sorularında tam 4 şık, ve sorunun metinden birebir kopyalanmamış olması. Geçersiz çıktılar temizlenir ya da reddedilir.
4. **İki aşamalı klasik soru:** Klasik sorularda model önce soruyu üretir. Ardından aynı parçaya bakarak ayrı bir çağrıyla, düşük sıcaklık (`temperature = 0`) kullanıp kısa bir cevap anahtarı yazar.

## Teknik Detaylar

| Alan | Kullanılan |
| --- | --- |
| Arayüz | Swift, SwiftUI (`NavigationStack`, `fileImporter`), `async/await`, `MainActor` |
| Yerel çıkarım | [swift-llama-cpp](https://github.com/pgorzelany/swift-llama-cpp) (llama.cpp), GPU (Metal) hızlandırma |
| Model | Özel veri setiyle fine-tune edilmiş, 4-bit kuantize edilmiş (Q4_K_M) GGUF model, yaklaşık 400 MB |
| Model eğitimi | Python, özel hazırlanmış soru-cevap veri seti, Google Colab |
| Prompt tasarımı | Sistem ve kullanıcı mesajları, kesin çıktı kuralları, JSON şeması, sabit `seed` ile tekrarlanabilir üretim |
| Dosya işleme | PDFKit, ZIPFoundation |
| PDF üretimi | `UIGraphicsPDFRenderer`, otomatik sayfa geçişi |

## Kurulum

**Gereksinimler:** Xcode 26 veya üstü, iOS 26.2 veya üstü. Gerçek cihaz önerilir, çünkü model GPU ile çalışır.

1. Repoyu klonlayın ve `SoruUreticiMobile.xcodeproj` dosyasını Xcode ile açın. Swift paketleri (swift-llama-cpp, ZIPFoundation) otomatik olarak indirilir.
2. **Model dosyasını ekleyin.** Model yaklaşık 400 MB olduğu için GitHub'da tutulmuyor. `soru_model_q4_k_m.gguf` dosyasını `SoruUreticiMobile/` klasörüne koyun ve uygulama hedefine (target) dahil olduğundan emin olun.
3. Signing ayarlarında kendi geliştirici hesabınızı (Team) seçin ve uygulamayı çalıştırın.

## Model Eğitimi

Modeli eğitmek için **4.315 örnekli Türkçe bir soru-cevap veri seti** hazırladım ve kalite kontrolünden geçirdim. Temizlik sonrası 4.180 örnek kaldı. Ardından Llama 3 8B modelini Unsloth ile LoRA kullanarak ince ayarladım. Veri seti, temizleme script'i ve eğitim kodu [`training/`](training/) klasöründe.

## Proje Yapısı

| Dosya | Görevi |
| --- | --- |
| `SoruUreticiMobileApp.swift` | Uygulamanın giriş noktası |
| `ContentView.swift` | Arayüz, metin çıkarma, model çağrısı, JSON ayrıştırma, doğrulama ve PDF üretimi |
| `training/` | Veri seti, veri temizleme ve LoRA eğitim kodu |

## Sonraki Adımlar

- `ContentView.swift` dosyasını katmanlara ayırmak (MVVM: View, ViewModel, servisler)
- Modeli uygulama açılışında bir kez yüklemek (şu an her üretimde yükleniyor)
- Cevap anahtarını ayrı bir sayfa olarak PDF'e eklemek
- Üretilen soruların kalitesini ölçmek için küçük bir değerlendirme seti hazırlamak
- Doğrulama ve metin işleme fonksiyonları için birim testleri yazmak

## Geliştirici

**Emine Yaren Almas** · [GitHub](https://github.com/yarenalms) · [LinkedIn](https://www.linkedin.com/in/yaren-almas-4280a3233) · [curtstudio.netlify.app](https://curtstudio.netlify.app)

# Model Eğitimi

Bu klasör, QuizMint'in soru üretici modelini eğitmek için hazırladığım **veri setini** ve **eğitim kodunu** içerir.

## Veri Seti

Türkçe ders notlarından (tarih, edebiyat vb.) alınmış kısa metin parçaları ve bunlara dayanan sınav soruları. Veri setini kendim hazırladım.

| | Ham | Temiz |
| --- | --- | --- |
| Toplam örnek | 4.315 | **4.180** |
| Çoktan seçmeli | 2.159 | 2.049 |
| Açık uçlu | 2.155 | 2.131 |
| Türü belirtilmemiş | 1 | 0 |

Her örnek bir bağlam metni, bir soru ve cevaptan oluşur. Test sorularında 4 şık da vardır:

```json
{
  "context": "Cumhuriyet 29 Ekim 1923'te ilan edilmiştir.",
  "question": "Cumhuriyet hangi tarihte ilan edilmiştir?",
  "options": ["23 Nisan 1920", "29 Ekim 1923", "19 Mayıs 1919", "30 Ağustos 1922"],
  "answer": "29 Ekim 1923",
  "type": "çoktan seçmeli"
}
```

### Temizleme

`clean_dataset.py` ham veriyi kalite kontrolünden geçirir:

| Kontrol | Etkilenen örnek |
| --- | --- |
| Soru, bağlam veya cevabı eksik | 29 → çıkarıldı |
| Test sorusunda 4 benzersiz şık yok ya da cevap şıklar arasında değil | 74 → çıkarıldı |
| Aynı bağlam + soru tekrarı | 32 → çıkarıldı |
| Yazım hatalı soru türü (`açık_uçlu`, `açık ulu`…) | 7 → düzeltildi |

```bash
python clean_dataset.py data/ders_dataset_raw.json data/ders_dataset_clean.json
```

## Eğitim

`train_lora.py`, Google Colab'da GPU ile çalışır.

| Ayar | Değer |
| --- | --- |
| Temel model | Llama 3 8B (4-bit, `unsloth/llama-3-8b-bnb-4bit`) |
| Yöntem | LoRA ile denetimli ince ayar (SFT): `r=16`, `alpha=16`, tüm attention ve MLP projeksiyonları |
| Kütüphaneler | Unsloth, Hugging Face TRL ve Transformers |
| Prompt formatı | Alpaca: Talimat / Bağlam / Yanıt |
| Optimizasyon | AdamW 8-bit, öğrenme oranı 2e-4, efektif batch 8, 120 adım |

**Neden LoRA?** Modelin 8 milyar parametresinin tamamını eğitmek yerine her katmana küçük adaptör matrisleri eklenir ve sadece onlar eğitilir. Model 4-bit yüklendiği için bu eğitim ücretsiz bir Colab GPU'suna sığar.

> Uygulamanın içinde çalışan model, telefona sığması için 4-bit (Q4_K_M) GGUF formatına dönüştürülmüş, yaklaşık 400 MB'lık daha küçük bir modeldir.

# -*- coding: utf-8 -*-
"""QuizMint — LoRA ile soru üretici model eğitimi (Google Colab, GPU).

Colab'da çalıştırmadan önce şu paketleri kurun:
    !pip install unsloth unsloth_zoo

Hugging Face'e yüklemek için anahtarı KODA YAZMAYIN.
Colab'da soldaki anahtar simgesinden (Secrets) HF_TOKEN adıyla ekleyin.
"""

import json

import torch  # noqa: F401  (unsloth GPU ortamını kontrol eder)
from datasets import Dataset
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import FastLanguageModel, is_bfloat16_supported

# ---------------------------------------------------------------------------
# 1. Temel modeli 4-bit olarak yükle ve LoRA adaptörlerini ekle
# ---------------------------------------------------------------------------
max_seq_length = 2048

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3-8b-bnb-4bit",
    max_seq_length=max_seq_length,
    dtype=None,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
    lora_alpha=16,
    lora_dropout=0,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# ---------------------------------------------------------------------------
# 2. Veri setini Alpaca formatına dönüştür
# ---------------------------------------------------------------------------
DATASET_PATH = "data/ders_dataset_clean.json"

alpaca_prompt = """### Talimat:
{}

### Bağlam (Metin):
{}

### Yanıt:
{}"""

with open(DATASET_PATH, "r", encoding="utf-8") as f:
    raw_data = json.load(f)

formatted_data = []
skipped = 0
for i, item in enumerate(raw_data):
    try:
        instruction = "Verilen metne dayanarak bir sınav sorusu hazırla."
        context = item.get("context", "Bağlam belirtilmemiş.")
        question = item["question"]
        answer = item["answer"]
        q_type = item.get("type", "açık uçlu")

        if q_type == "çoktan seçmeli" and "options" in item:
            options_str = "\n".join(f"- {opt}" for opt in item["options"])
            response = f"Soru: {question}\nSeçenekler:\n{options_str}\nDoğru Cevap: {answer}"
        else:
            response = f"Soru: {question}\nCevap: {answer}"

        text = alpaca_prompt.format(instruction, context, response) + tokenizer.eos_token
        formatted_data.append({"text": text})
    except KeyError as e:
        print(f"{i}. örnekte {e} alanı eksik, atlanıyor.")
        skipped += 1

dataset = Dataset.from_list(formatted_data)
print(f"Dönüştürülen örnek: {len(dataset)}  |  Atlanan: {skipped}")

# ---------------------------------------------------------------------------
# 3. Eğitim (SFT + LoRA)
# ---------------------------------------------------------------------------
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=max_seq_length,
    dataset_num_proc=2,
    args=TrainingArguments(
        per_device_train_batch_size=2,
        gradient_accumulation_steps=4,   # efektif batch boyutu = 2 x 4 = 8
        warmup_steps=5,
        max_steps=120,
        learning_rate=2e-4,
        fp16=not is_bfloat16_supported(),
        bf16=is_bfloat16_supported(),
        logging_steps=1,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        seed=3407,
        output_dir="outputs",
    ),
)
trainer.train()

# ---------------------------------------------------------------------------
# 4. Hızlı test
# ---------------------------------------------------------------------------
FastLanguageModel.for_inference(model)


def soru_uret(metin: str, talimat: str = "Verilen metne dayanarak bir sınav sorusu hazırla.") -> str:
    inputs = tokenizer([alpaca_prompt.format(talimat, metin, "")], return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=256)
    return tokenizer.batch_decode(outputs)[0].split("### Yanıt:")[1].replace(tokenizer.eos_token, "").strip()


print(soru_uret("Tanzimat Fermanı 1839 yılında ilan edilmiştir. Osmanlı Devleti'nde modernleşme sürecini başlatmıştır."))
print(soru_uret(
    "Lale Devri, 1718 Pasarofça Antlaşması ile başlayıp 1730 Patrona Halil İsyanı ile sona eren dönemdir.",
    "Verilen metne dayanarak AÇIK UÇLU bir sınav sorusu hazırla.",
))

# ---------------------------------------------------------------------------
# 5. (İsteğe bağlı) LoRA adaptörünü Hugging Face'e yükle
# ---------------------------------------------------------------------------
# from google.colab import userdata
# model.push_to_hub_merged(
#     "KULLANICI_ADI/quizmint-soru-uretici",
#     tokenizer,
#     save_method="lora",
#     token=userdata.get("HF_TOKEN"),
# )

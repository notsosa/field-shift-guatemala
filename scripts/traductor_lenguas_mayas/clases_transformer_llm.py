import torch
from torch.utils.data import Dataset, DataLoader
from transformers import MT5ForConditionalGeneration, MT5Tokenizer, AdamW

class MayanTranslationDataset(Dataset):
    """
    Clase para preparar y manejar el conjunto de datos de entrenamiento 
    (parejas de texto: Español -> Lengua Maya con su respectivo identificador).
    """
    def __init__(self, data, tokenizer, max_length=128):
        self.tokenizer = tokenizer
        self.inputs = data["spanish_texts"]
        self.targets = data["maya_texts"]
        self.max_length = max_length

    def __len__(self):
        return len(self.inputs)

    def __getitem__(self, idx):
        source_text = str(self.inputs[idx])
        target_text = str(self.targets[idx])

        # Tokenizar el texto de entrada (Español)
        source_encoding = self.tokenizer(
            source_text,
            max_length=self.max_length,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )

        # Tokenizar el texto de salida (Lengua Maya)
        target_encoding = self.tokenizer(
            target_text,
            max_length=self.max_length,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )

        labels = target_encoding["input_ids"]
        # Reemplazar los tokens de relleno (padding) por -100 para que la pérdida no los penalice
        labels[labels == self.tokenizer.pad_token_id] = -100

        return {
            "input_ids": source_encoding["input_ids"].flatten(),
            "attention_mask": source_encoding["attention_mask"].flatten(),
            "labels": labels.flatten()
        }

class MayanEncoderDecoderModel:
    """
    Clase principal que envuelve el modelo Encoder-Decoder basado en Transformers
    para la traducción agrícola multilingüe.
    """
    def __init__(self, model_name="google/mt5-small", device=None):
        self.device = device if device else ("cuda" if torch.cuda.is_available() else "cpu")
        print(f"Utilizando dispositivo: {self.device}")
        
        # Cargar el tokenizador y el modelo Encoder-Decoder preentrenado
        self.tokenizer = MT5Tokenizer.from_pretrained(model_name)
        self.model = MT5ForConditionalGeneration.from_pretrained(model_name)
        self.model.to(self.device)

    def train_model(self, train_dataset, epochs=3, batch_size=8, lr=5e-5):
        """
        Bucle de entrenamiento básico para ajustar el modelo a nuestras lenguas mayas.
        """
        train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
        optimizer = AdamW(self.model.parameters(), lr=lr)
        
        self.model.train()
        for epoch in range(epochs):
            total_loss = 0
            for batch in train_loader:
                optimizer.zero_grad()
                
                input_ids = batch["input_ids"].to(self.device)
                attention_mask = batch["attention_mask"].to(self.device)
                labels = batch["labels"].to(self.device)

                # Forward pass a través del Encoder y Decoder
                outputs = self.model(
                    input_ids=input_ids,
                    attention_mask=attention_mask,
                    labels=labels
                )
                
                loss = outputs.loss
                total_loss += loss.item()

                # Backward pass y actualización de pesos
                loss.backward()
                optimizer.step()

            print(f"Época {epoch + 1}/{epochs} - Pérdida (Loss): {total_loss / len(train_loader):.4f}")

    def translate(self, spanish_text, target_language_prefix="traducir a kaqchikel: "):
        """
        Realiza la traducción de una recomendación agrícola del español a la lengua maya deseada.
        """
        self.model.eval()
        # Añadimos un prefijo contextual para guiar al modelo multilingüe
        input_text = target_language_prefix + spanish_text
        
        input_encoding = self.tokenizer(
            input_text,
            return_tensors="pt",
            max_length=128,
            truncation=True
        ).to(self.device)

        with torch.no_grad():
            # El Decoder genera los tokens de la traducción uno por uno
            generated_tokens = self.model.generate(
                input_ids=input_encoding["input_ids"],
                attention_mask=input_encoding["attention_mask"],
                max_length=128,
                num_beams=4,
                early_stopping=True
            )

        translated_text = self.tokenizer.decode(generated_tokens[0], skip_special_tokens=True)
        return translated_text

# ==========================================
# Ejemplo de uso práctico para el prototipo
# ==========================================
if __name__ == "__main__":
    # 1. Datos simulados de ejemplo (En tu app real, aquí conectarás los textos generados por datos de la NASA)
    sample_data = {
        "spanish_texts": [
            "Se recomienda regar el cultivo de maíz hoy debido a las altas temperaturas.",
            "Hay riesgo de helada la próxima madrugada, proteja sus plantas."
        ],
        "maya_texts": [
            "[Kaqchikel traducido de ejemplo]", 
            "[K'iche traducido de ejemplo]"
        ]
    }

    # 2. Inicializar tokenizador y dataset
    model_wrapper = MayanEncoderDecoderModel(model_name="google/mt5-small")
    
    dataset = MayanTranslationDataset(sample_data, model_wrapper.tokenizer)

    # 3. Simular entrenamiento (Fine-tuning)
    print("\nIniciando ajuste fino (Fine-tuning) del modelo Encoder-Decoder...")
    # model_wrapper.train_model(dataset, epochs=1) # Descomentar cuando tengas tu dataset real

    # 4. Prueba de traducción (Inferencia)
    consejo_nasa = "Se recomienda regar el cultivo de maíz hoy debido a las altas temperaturas."
    traduccion = model_wrapper.translate(consejo_nasa, target_language_prefix="translate to kaqchikel: ")
    print(f"\nTexto en Español: {consejo_nasa}")
    print(f"Traducción generada: {traduccion}")
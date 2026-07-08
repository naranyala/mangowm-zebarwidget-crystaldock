# OCWS AI Runner

The `ocws-llm-runner` is a native C/GTK3 desktop client designed to interface smoothly with a local, open-source Python LLM server. It allows you to chat with powerful local AI models directly from your desktop and leverages integrated OCR to read text from your screen.

## Features

- **Native UI:** A gorgeous, glassmorphic GTK3 chat interface that visually matches the rest of the OCWS ecosystem.
- **Model Management:** Automatically scans for and allows you to dynamically load/eject `.gguf` language models from `~/Models/` without needing to restart the app.
- **Seamless OCR Integration:** Features a built-in `OCR ` button that triggers a screen capture, extracts the text using Tesseract, and pastes it instantly into your chat prompt.
- **Session Continuity:** The Python backend safely manages chat history context across multi-turn conversations.

## Installation & Setup

1. **Install Python Dependencies:**
   The `ocws-llm-runner` leverages a Python backend that utilizes `llama-cpp-python`. You'll need to install it:
   ```bash
   pip install llama-cpp-python
   ```
2. **Download Models:**
   Create a folder at `~/Models` and download your preferred quantized `.gguf` files there (e.g., Qwen2.5-Coder-3B or LLaMA-3.1-8B).
   ```bash
   mkdir -p ~/Models
   ```

## Usage

Simply launch **OCWS Assistant** from your app launcher (or type `ocws-llm-runner` in the terminal).

1. Select your downloaded model from the dropdown header.
2. Click **Load**.
3. Type your query or click **OCR ** to grab code/text from anywhere on your screen.
4. When finished, hit **Eject** to instantly free up your RAM/VRAM!

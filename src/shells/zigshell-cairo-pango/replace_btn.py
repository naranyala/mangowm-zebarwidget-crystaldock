import os

file_path = "src/panel.zig"
with open(file_path, "r") as f:
    content = f.read()

content = content.replace("btn != 1", "btn != 272")
content = content.replace("btn == 1", "btn == 272")

with open(file_path, "w") as f:
    f.write(content)

print("Replaced all btn != 1 with btn != 272 in panel.zig")

from PIL import Image
import os

ICON_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def convert_image(input_path, output_format, size="original", keep_ratio=True):
    try:
        img = Image.open(input_path)

        # Ajuste de cor / transparência
        has_alpha = "A" in img.getbands()

        if output_format.lower() in {"jpg", "jpeg", "pdf"} and has_alpha:
            background = Image.new("RGB", img.size, (255, 255, 255))
            alpha = img.convert("RGBA")
            background.paste(alpha, mask=alpha.getchannel("A"))
            img = background
        elif has_alpha:
            img = img.convert("RGBA")
        else:
            img = img.convert("RGB")

        # Redimensionamento
        if size and str(size).lower() != "original":
            width, height = map(int, str(size).lower().split("x"))

            if keep_ratio:
                img.thumbnail((width, height), Image.LANCZOS)
            else:
                img = img.resize((width, height), Image.LANCZOS)

        base_name = os.path.splitext(input_path)[0]
        ext = output_format.lower()
        output_path = f"{base_name}.{ext}"

        if ext == "ico":
            icon_source = img.convert("RGBA") if img.mode != "RGBA" else img
            output_path = f"{base_name}.ico"
            icon_source.save(output_path, format="ICO", sizes=ICON_SIZES)
        elif ext == "pdf":
            output_path = f"{base_name}.pdf"
            img.convert("RGB").save(output_path, "PDF", resolution=100.0)
        elif ext in {"jpg", "jpeg"}:
            output_path = f"{base_name}.jpg"
            img.convert("RGB").save(output_path, "JPEG", quality=95, optimize=True)
        elif ext == "png":
            output_path = f"{base_name}.png"
            img.save(output_path, "PNG")
        elif ext == "webp":
            output_path = f"{base_name}.webp"
            img.save(output_path, "WEBP", quality=95, method=6)
        elif ext == "bmp":
            output_path = f"{base_name}.bmp"
            img.convert("RGB").save(output_path, "BMP")
        elif ext == "tiff":
            output_path = f"{base_name}.tiff"
            img.save(output_path, "TIFF")
        elif ext == "gif":
            output_path = f"{base_name}.gif"
            img.save(output_path, "GIF")
        else:
            return f"[ERRO] Formato de saída não suportado: {output_format}"

        return f"[OK] Convertido com sucesso: {output_path}"

    except Exception as e:
        return f"[ERRO] {str(e)}"

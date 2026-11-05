import sys
import os
import json
import cv2
import numpy as np
from PIL import ImageGrab

def parse_rect(rect_str):
    try:
        parts = [int(p) for p in rect_str.split(",")]
        if len(parts) == 4:
            return parts
    except Exception:
        pass
    return None

def merge_question_blocks(blocks, max_v_gap=220):
    """
    Menyatukan blok-blok teks yang sejajar secara vertikal (misal: kalimat soal di atas
    dan daftar pilihan ganda a, b, c, d, e di bawahnya) menjadi satu bounding box utuh.
    """
    if not blocks:
        return []

    # Format block: [x1, y1, x2, y2, chars]
    merged = [list(b) for b in blocks]
    changed = True
    while changed:
        changed = False
        new_merged = []
        used = [False] * len(merged)
        for i in range(len(merged)):
            if used[i]:
                continue
            bx1, by1, bx2, by2, bchars = merged[i]
            for j in range(i + 1, len(merged)):
                if used[j]:
                    continue
                ox1, oy1, ox2, oy2, ochars = merged[j]

                # Cek jarak vertikal antar blok
                v_gap = max(0, max(by1, oy1) - min(by2, oy2))
                if v_gap <= max_v_gap:
                    # Cek keselarasan horizontal (overlap horizontal atau batas kiri sejajar)
                    h_overlap = min(bx2, ox2) - max(bx1, ox1)
                    min_w = min(bx2 - bx1, ox2 - ox1)
                    left_diff = abs(bx1 - ox1)

                    if h_overlap > 0.25 * min_w or (left_diff <= 100 and h_overlap > -40):
                        bx1 = min(bx1, ox1)
                        by1 = min(by1, oy1)
                        bx2 = max(bx2, ox2)
                        by2 = max(by2, oy2)
                        bchars += ochars
                        used[j] = True
                        changed = True
            used[i] = True
            new_merged.append([bx1, by1, bx2, by2, bchars])
        merged = new_merged
    return merged

def detect_question_box(exclude_rects=None, out_crop_path=None, input_image_path=None):
    # 1. Tangkap layar penuh secara silent (atau baca gambar uji jika ada)
    if input_image_path and os.path.exists(input_image_path):
        img = cv2.imread(input_image_path)
    else:
        screen = ImageGrab.grab()
        img = cv2.cvtColor(np.array(screen), cv2.COLOR_RGB2BGR)

    if img is None:
        return {"status": "error", "message": "Gagal mengambil gambar layar"}

    H, W = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 2. Buat mask area valid (abaikan navbar/tab browser atas, taskbar bawah, dan jendela Gemini/GUI)
    valid_mask = np.ones((H, W), dtype=np.uint8) * 255
    top_margin = int(H * 0.07)
    bottom_margin = int(H * 0.93)
    valid_mask[:top_margin, :] = 0
    valid_mask[bottom_margin:, :] = 0

    if exclude_rects:
        for r in exclude_rects:
            if r:
                ex, ey, ew, eh = r
                x1 = max(0, ex - 8)
                y1 = max(0, ey - 8)
                x2 = min(W, ex + ew + 8)
                y2 = min(H, ey + eh + 8)
                if x2 > x1 and y2 > y1:
                    valid_mask[y1:y2, x1:x2] = 0

    # 3. Deteksi tepi karakter teks menggunakan morfologi gradien (tahan terhadap background putih/pink/gelap)
    kernel_grad = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    grad = cv2.morphologyEx(gray, cv2.MORPH_GRADIENT, kernel_grad)

    # Binarisasi Otsu pada gradien
    _, bw = cv2.threshold(grad, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    bw = cv2.bitwise_and(bw, valid_mask)

    # 4. Filter komponen berdasarkan ukuran huruf (buang garis tabel panjang / gambar besar / titik noise)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(bw, connectivity=8)
    char_mask = np.zeros((H, W), dtype=np.uint8)
    char_count_map = np.zeros((H, W), dtype=np.uint8)

    for i in range(1, num_labels):
        cx, cy, cw, ch, area = stats[i]
        # Ukuran huruf standar soal ujian di layar: tinggi 6px - 28px, lebar 2px - 55px (abaikan judul banner raksasa)
        if 6 <= ch <= 28 and 2 <= cw <= 55 and 10 <= area <= 1200:
            aspect = cw / float(ch)
            if 0.08 <= aspect <= 4.5:
                char_mask[cy:cy+ch, cx:cx+cw] = bw[cy:cy+ch, cx:cx+cw]
                char_count_map[cy + ch // 2, cx + cw // 2] = 1

    # 5. Dilasi morfologi untuk menyatukan huruf -> kata -> baris kalimat
    kernel_line = cv2.getStructuringElement(cv2.MORPH_RECT, (65, 28))
    connected = cv2.morphologyEx(char_mask, cv2.MORPH_CLOSE, kernel_line)
    connected = cv2.dilate(connected, cv2.getStructuringElement(cv2.MORPH_RECT, (20, 14)), iterations=1)

    contours, _ = cv2.findContours(connected, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    integral_chars = cv2.integral(char_count_map)

    raw_blocks = []
    for cnt in contours:
        x, y, w, h = cv2.boundingRect(cnt)
        if w < 45 or h < 12:
            continue
        if w > W * 0.96 and h > H * 0.90:
            continue

        num_chars = int(
            integral_chars[y + h, x + w]
            - integral_chars[y, x + w]
            - integral_chars[y + h, x]
            + integral_chars[y, x]
        )
        if num_chars < 4:
            continue

        raw_blocks.append([x, y, x + w, y + h, num_chars])

    # 6. Satukan blok kalimat soal & blok pilihan ganda yang sejajar vertikal
    merged_blocks = merge_question_blocks(raw_blocks, max_v_gap=int(H * 0.24))

    best_box = None
    best_score = 0.0

    for b in merged_blocks:
        x1, y1, x2, y2, num_chars = b
        w = x2 - x1
        h = y2 - y1

        # Filter ukuran minimal area soal
        if w < 140 or h < 30 or num_chars < 15:
            continue

        area = float(w * h)
        density = num_chars / (area / 1000.0 + 1.0)

        center_x = x1 + w / 2.0
        center_y = y1 + h / 2.0

        pos_weight = 1.0
        if 0.08 * W <= center_x <= 0.85 * W and 0.10 * H <= center_y <= 0.88 * H:
            pos_weight = 1.35

        size_bonus = 1.25 if (w >= 200 and h >= 80) else 1.0

        score = (num_chars * 3.0 + (area ** 0.42)) * pos_weight * size_bonus
        if density < 0.10:
            score *= 0.4

        if score > best_score:
            best_score = score
            best_box = (x1, y1, w, h, int(num_chars))

    if best_box is None:
        return {"status": "empty", "message": "Area teks soal tidak ditemukan"}

    bx, by, bw_box, bh_box, nchars = best_box

    # Tambahkan padding aman di sekeliling teks soal agar huruf pinggir tidak terpotong
    pad_x = 18
    pad_y = 14
    fx = max(0, bx - pad_x)
    fy = max(0, by - pad_y)
    fw = min(W - fx, bw_box + 2 * pad_x)
    fh = min(H - fy, bh_box + 2 * pad_y)

    if out_crop_path:
        cropped = img[fy:fy+fh, fx:fx+fw]
        cv2.imwrite(out_crop_path, cropped)

    return {
        "status": "ok",
        "x": int(fx),
        "y": int(fy),
        "w": int(fw),
        "h": int(fh),
        "chars": int(nchars)
    }

if __name__ == "__main__":
    exclude_list = []
    out_result_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ocr_auto_result.json")
    out_crop = None
    in_img = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--exclude" and i + 1 < len(args):
            r = parse_rect(args[i + 1])
            if r:
                exclude_list.append(r)
            i += 2
        elif args[i] == "--out" and i + 1 < len(args):
            out_result_file = args[i + 1]
            i += 2
        elif args[i] == "--crop" and i + 1 < len(args):
            out_crop = args[i + 1]
            i += 2
        elif args[i] == "--image" and i + 1 < len(args):
            in_img = args[i + 1]
            i += 2
        else:
            i += 1

    try:
        res = detect_question_box(exclude_rects=exclude_list, out_crop_path=out_crop, input_image_path=in_img)
    except Exception as e:
        res = {"status": "error", "message": str(e)}

    try:
        with open(out_result_file, "w", encoding="utf-8") as f:
            json.dump(res, f)
    except Exception:
        pass
    print(json.dumps(res))

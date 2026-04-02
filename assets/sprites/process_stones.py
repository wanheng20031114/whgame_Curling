import sys
import os

try:
    from PIL import Image
except ImportError:
    import subprocess
    print("Pillow not found, installing...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image

def process_image(input_path, output_path, target_size=(64, 64), tolerance=40):
    try:
        img = Image.open(input_path).convert("RGBA")
    except Exception as e:
        print(f"Error opening {input_path}: {e}")
        return

    width, height = img.size
    pixels = img.load()
    
    # 用于记录背景蒙版的二维数组
    mask = [[False for _ in range(height)] for _ in range(width)]
    
    # 判断像素是否接近纯白
    def is_white_bg(c):
        return c[0] > 255 - tolerance and c[1] > 255 - tolerance and c[2] > 255 - tolerance

    # 从四个角开始做 BFS 泛洪填充，精确去掉背景白，保留冰壶内部的高光白
    q = []
    corners = [(0, 0), (width-1, 0), (0, height-1), (width-1, height-1)]
    for x, y in corners:
        if is_white_bg(pixels[x, y]):
            mask[x][y] = True
            q.append((x, y))
            
    head = 0
    while head < len(q):
        x, y = q[head]
        head += 1
        
        for dx, dy in [(1,0), (-1,0), (0,1), (0,-1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                if not mask[nx][ny] and is_white_bg(pixels[nx, ny]):
                    mask[nx][ny] = True
                    q.append((nx, ny))
                    
    # 根据蒙版把背景变透明，并找出冰壶的边界 bounding box
    min_x, min_y = width, height
    max_x, max_y = 0, 0
    
    for x in range(width):
        for y in range(height):
            if mask[x][y]:
                # 变成完全透明
                pixels[x, y] = (255, 255, 255, 0)
            else:
                # 记录存在的最值
                if x < min_x: min_x = x
                if y < min_y: min_y = y
                if x > max_x: max_x = x
                if y > max_y: max_y = y
                
    if min_x > max_x or min_y > max_y:
        print(f"Image {input_path} is completely transparent or white!")
        return
        
    # 基于 Bounding Box 进行裁切（取最大的边来裁切出一个正方形，防止拉伸）
    bb_width = max_x - min_x + 1
    bb_height = max_y - min_y + 1
    side = max(bb_width, bb_height)
    
    center_x = min_x + bb_width // 2
    center_y = min_y + bb_height // 2
    
    # 计算正方形裁剪区域
    crop_min_x = max(0, center_x - side // 2)
    crop_min_y = max(0, center_y - side // 2)
    crop_max_x = crop_min_x + side
    crop_max_y = crop_min_y + side
    
    cropped = img.crop((crop_min_x, crop_min_y, crop_max_x, crop_max_y))
    
    # 缩放到游戏所需尺寸 (64x64)
    resized = cropped.resize(target_size, Image.Resampling.LANCZOS)
    
    # 保存结果
    resized.save(output_path, "PNG")
    print(f"✅ 处理完成: {input_path} -> {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python process_stones.py <input_img> <output_img>")
        sys.exit(1)
    
    process_image(sys.argv[1], sys.argv[2])

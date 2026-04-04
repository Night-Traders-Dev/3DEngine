gc_disable()
# -----------------------------------------
# ui_text.sage - Text rendering for Sage Engine Editor
# Fast mode: 1 quad per character (solid block with gaps for readability)
# Detailed mode: pixel-accurate bitmap font (slower, for static text)
# -----------------------------------------

# ============================================================================
# 4x6 bitmap font (each char is a 24-bit bitmask, 4 wide x 6 tall)
# Row-major, MSB first. 1=pixel on, 0=off.
# Stored as array of 6 integers (one per row, 4 bits each)
# ============================================================================
proc _get_glyph(ch):
    # Returns [row0, row1, row2, row3, row4, row5] each 0-15 (4 bits)
    if ch == "A":
        return [6,9,15,9,9,0]
    if ch == "B":
        return [14,9,14,9,14,0]
    if ch == "C":
        return [6,9,8,8,6,0]
    if ch == "D":
        return [14,9,9,9,14,0]
    if ch == "E":
        return [15,8,14,8,15,0]
    if ch == "F":
        return [15,8,14,8,8,0]
    if ch == "G":
        return [6,8,11,9,6,0]
    if ch == "H":
        return [9,9,15,9,9,0]
    if ch == "I":
        return [14,4,4,4,14,0]
    if ch == "J":
        return [1,1,1,9,6,0]
    if ch == "K":
        return [9,10,12,10,9,0]
    if ch == "L":
        return [8,8,8,8,15,0]
    if ch == "M":
        return [9,15,15,9,9,0]
    if ch == "N":
        return [9,13,15,11,9,0]
    if ch == "O":
        return [6,9,9,9,6,0]
    if ch == "P":
        return [14,9,14,8,8,0]
    if ch == "Q":
        return [6,9,9,10,5,0]
    if ch == "R":
        return [14,9,14,10,9,0]
    if ch == "S":
        return [7,8,6,1,14,0]
    if ch == "T":
        return [15,4,4,4,4,0]
    if ch == "U":
        return [9,9,9,9,6,0]
    if ch == "V":
        return [9,9,9,6,6,0]
    if ch == "W":
        return [9,9,15,15,9,0]
    if ch == "X":
        return [9,9,6,9,9,0]
    if ch == "Y":
        return [9,9,6,4,4,0]
    if ch == "Z":
        return [15,1,6,8,15,0]
    if ch == "a":
        return [0,6,1,7,7,0]
    if ch == "b":
        return [8,8,14,9,14,0]
    if ch == "c":
        return [0,0,7,8,7,0]
    if ch == "d":
        return [1,1,7,9,7,0]
    if ch == "e":
        return [0,6,15,8,6,0]
    if ch == "f":
        return [3,4,14,4,4,0]
    if ch == "g":
        return [0,7,9,7,1,6]
    if ch == "h":
        return [8,8,14,9,9,0]
    if ch == "i":
        return [4,0,4,4,4,0]
    if ch == "j":
        return [2,0,2,2,2,12]
    if ch == "k":
        return [8,10,12,10,9,0]
    if ch == "l":
        return [12,4,4,4,14,0]
    if ch == "m":
        return [0,0,9,15,9,0]
    if ch == "n":
        return [0,0,14,9,9,0]
    if ch == "o":
        return [0,0,6,9,6,0]
    if ch == "p":
        return [0,14,9,14,8,8]
    if ch == "q":
        return [0,7,9,7,1,1]
    if ch == "r":
        return [0,0,11,12,8,0]
    if ch == "s":
        return [0,7,12,3,14,0]
    if ch == "t":
        return [4,14,4,4,3,0]
    if ch == "u":
        return [0,0,9,9,7,0]
    if ch == "v":
        return [0,0,9,6,6,0]
    if ch == "w":
        return [0,0,9,15,6,0]
    if ch == "x":
        return [0,0,9,6,9,0]
    if ch == "y":
        return [0,9,9,7,1,6]
    if ch == "z":
        return [0,15,2,4,15,0]
    if ch == "0":
        return [6,9,9,9,6,0]
    if ch == "1":
        return [2,6,2,2,7,0]
    if ch == "2":
        return [6,1,2,4,15,0]
    if ch == "3":
        return [14,1,6,1,14,0]
    if ch == "4":
        return [2,6,10,15,2,0]
    if ch == "5":
        return [15,8,14,1,14,0]
    if ch == "6":
        return [6,8,14,9,6,0]
    if ch == "7":
        return [15,1,2,4,4,0]
    if ch == "8":
        return [6,9,6,9,6,0]
    if ch == "9":
        return [6,9,7,1,6,0]
    if ch == " ":
        return [0,0,0,0,0,0]
    if ch == ".":
        return [0,0,0,0,4,0]
    if ch == ",":
        return [0,0,0,2,2,4]
    if ch == ":":
        return [0,4,0,4,0,0]
    if ch == ";":
        return [0,4,0,4,4,0]
    if ch == "-":
        return [0,0,15,0,0,0]
    if ch == "+":
        return [0,4,14,4,0,0]
    if ch == "=":
        return [0,15,0,15,0,0]
    if ch == "(":
        return [2,4,4,4,2,0]
    if ch == ")":
        return [4,2,2,2,4,0]
    if ch == "[":
        return [6,4,4,4,6,0]
    if ch == "]":
        return [6,2,2,2,6,0]
    if ch == "/":
        return [1,1,2,4,8,0]
    if ch == "_":
        return [0,0,0,0,15,0]
    if ch == "#":
        return [10,15,10,15,10,0]
    if ch == "!":
        return [4,4,4,0,4,0]
    if ch == "?":
        return [6,1,2,0,2,0]
    if ch == "<":
        return [1,2,4,2,1,0]
    if ch == ">":
        return [4,2,1,2,4,0]
    if ch == "|":
        return [4,4,4,4,4,0]
    if ch == "*":
        return [0,9,6,9,0,0]
    if ch == "@":
        return [6,9,11,8,7,0]
    if ch == "%":
        return [9,1,6,8,9,0]
    # Unknown char = solid block
    return [15,15,15,15,15,0]

# ============================================================================
# Build quads for a text string
# Returns array of {x, y, w, h, color} quads
# ============================================================================
proc build_text_quads(text, start_x, start_y, pixel_size, color):
    let quads = []
    let char_w = 4 * pixel_size + pixel_size
    let char_h = 6 * pixel_size + pixel_size
    let cx = start_x
    let ci = 0
    while ci < len(text):
        let ch = text[ci]
        if ch == chr(10):
            cx = start_x
            start_y = start_y + char_h
            ci = ci + 1
            continue
        let glyph = _get_glyph(ch)
        let row = 0
        while row < 6:
            let bits = glyph[row]
            let col = 0
            while col < 4:
                let bit = bits >> (3 - col)
                if bit - (bit >> 1) * 2 == 1:
                    let px = cx + col * pixel_size
                    let py = start_y + row * pixel_size
                    push(quads, {"x": px, "y": py, "w": pixel_size, "h": pixel_size, "color": color})
                col = col + 1
            row = row + 1
        cx = cx + char_w
        ci = ci + 1
    return quads

# ============================================================================
# Measure text dimensions
# ============================================================================
proc measure_text(text, pixel_size):
    let char_w = 4 * pixel_size + pixel_size
    let char_h = 6 * pixel_size + pixel_size
    let max_w = 0
    let cur_w = 0
    let lines = 1
    let i = 0
    while i < len(text):
        if text[i] == chr(10):
            if cur_w > max_w:
                max_w = cur_w
            cur_w = 0
            lines = lines + 1
        else:
            cur_w = cur_w + char_w
        i = i + 1
    if cur_w > max_w:
        max_w = cur_w
    return [max_w, char_h * lines]

# ============================================================================
# FAST text rendering: 1 quad per character (row-merged)
# Much faster than per-pixel, good enough for editor UI
# Merges consecutive lit pixels in each row into single quads
# ============================================================================
proc build_text_quads_fast(text, start_x, start_y, char_size, color):
    let quads = []
    let char_w = char_size * 5
    let char_h = char_size * 7
    let px_w = char_size
    let px_h = char_size
    let cx = start_x
    let ci = 0
    while ci < len(text):
        let ch = text[ci]
        if ch == " ":
            cx = cx + char_w
            ci = ci + 1
            continue
        if ch == chr(10):
            cx = start_x
            start_y = start_y + char_h
            ci = ci + 1
            continue
        let glyph = _get_glyph(ch)
        let row = 0
        while row < 6:
            let bits = glyph[row]
            if bits > 0:
                # Find runs of consecutive set bits and merge into one quad
                let col = 0
                while col < 4:
                    let bit = bits >> (3 - col)
                    if bit - (bit >> 1) * 2 == 1:
                        let run_start = col
                        col = col + 1
                        while col < 4:
                            let nb = bits >> (3 - col)
                            if nb - (nb >> 1) * 2 == 1:
                                col = col + 1
                            else:
                                col = 4
                        let run_len = col - run_start
                        if col > 4:
                            col = 4
                            run_len = 4 - run_start
                        push(quads, {"x": cx + run_start * px_w, "y": start_y + row * px_h, "w": run_len * px_w, "h": px_h, "color": color})
                    col = col + 1
            row = row + 1
        cx = cx + char_w
        ci = ci + 1
    return quads

# ============================================================================
# VECTOR text rendering using line-segment font (smooth, readable)
# Uses text_render.sage glyphs + native build_line_quads for speed
# ============================================================================
proc build_text_quads_vector(text, start_x, start_y, char_height, color):
    from text_render import build_text_lines
    let char_width = char_height * 0.6
    let lines = build_text_lines(text, start_x, start_y, char_width, char_height)
    let thickness = char_height * 0.13
    if thickness < 1.0:
        thickness = 1.0
    return build_line_quads(lines, thickness, color[0], color[1], color[2], color[3])

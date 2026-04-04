# random.sage - Random number generation utilities
# Provides math.random() and related functions

let _random_seed = 123456789

proc _random_next():
    # LCG parameters: a=1664525, c=1013904223, m=2^32
    _random_seed = (_random_seed * 1664525 + 1013904223) % 4294967296
    return _random_seed

proc random():
    return _random_next() / 4294967296.0

proc random_range(min_val, max_val):
    return min_val + random() * (max_val - min_val)

proc random_int(min_val, max_val):
    return int(random_range(min_val, max_val + 1))

# Type conversion functions
proc int(value):
    if value < 0:
        return 0 - floor(0 - value)
    return floor(value)

proc floor(value):
    let int_part = 0
    if value >= 0:
        while int_part <= value:
            int_part = int_part + 1
        return int_part - 1
    else:
        while int_part > value:
            int_part = int_part - 1
        return int_part

proc ceil(value):
    let int_part = floor(value)
    if value == int_part:
        return int_part
    if value > 0:
        return int_part + 1
    return int_part

proc round(value):
    if value >= 0:
        return floor(value + 0.5)
    return ceil(value - 0.5)
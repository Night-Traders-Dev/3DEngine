# test_textures.sage - Sanity checks for texture system (non-GPU parts)
from textures import create_texture_cache, has_texture, get_texture, texture_count

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== Texture System Sanity Checks ==="
let tc = create_texture_cache()
check("cache created", tc != nil)
check("has textures dict", dict_has(tc, "textures"))
check("default sampler -1", tc["default_sampler"] == -1)
# Manually insert for testing
tc["textures"]["_white"] = 0
tc["textures"]["test"] = 42
check("has_texture true", has_texture(tc, "test"))
check("has_texture false", has_texture(tc, "nonexistent") == false)
check("get_texture works", get_texture(tc, "test") == 42)
check("get missing returns white", get_texture(tc, "missing") == 0)
check("texture count", texture_count(tc) == 2)
print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Texture sanity checks failed!"
else:
    print "All texture sanity checks passed!"

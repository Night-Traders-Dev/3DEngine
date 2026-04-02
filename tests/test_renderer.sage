# test_renderer.sage - Non-GPU sanity checks for renderer boot helpers

from renderer import get_pipeline_cache, _store_pipeline_cache_result

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Renderer Sanity Checks ==="

check("pipeline cache starts disabled", get_pipeline_cache() == false)
check("store false stays disabled", _store_pipeline_cache_result(false) == false)
check("pipeline cache remains disabled", get_pipeline_cache() == false)
check("store true enables cache", _store_pipeline_cache_result(true) == true)
check("pipeline cache remains enabled", get_pipeline_cache() == true)
check("non-bool value does not enable cache", _store_pipeline_cache_result(1) == false)
check("pipeline cache disabled after non-bool", get_pipeline_cache() == false)

print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Renderer sanity checks failed!"
else:
    print "All renderer sanity checks passed!"

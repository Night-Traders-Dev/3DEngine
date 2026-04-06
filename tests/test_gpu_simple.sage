import gpu

print "Checking gpu module attributes..."

# Try to list available functions
print "Available in gpu:"
let keys = dict_keys(gpu)
print str(keys)
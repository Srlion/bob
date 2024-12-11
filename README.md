# bob

human readable serializer for lua

## Usage

```lua
local bob = include("bob.lua")
local data = {
    foo = "bar",
    bar = 123,
    baz = {
        "a",
        "b",
        "c"
    }
}
local encoded = bob.encode(data)
print(encoded)

local decoded = bob.decode(encoded)
print(decoded)
```

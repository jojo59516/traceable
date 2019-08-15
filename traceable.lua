local traceable = {}
local _M = traceable

local null = setmetatable({}, { __tostring = function () return "null"end })
_M.null = null

local function merge(dst, src)
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

local function normalize_field_path(field_path)
    return field_path:gsub("^([-?%d]+)", "[%1]")
                    :gsub("%.([-?%d]+)", "[%1]")
                    :gsub("^([^.%[%]]+)", "['%1']")
                    :gsub("%.([^.%[%]]+)", "['%1']")
end

local getter_template = [[
    return function(t)
        local success, value = pcall(function (t)
            return t%s
        end, t)
        if success then
            return value
        end
    end
]]
local setter_template = [[
    return function(t, v)
        local success, err = pcall(function (t, v)
            t%s = v
        end, t, v)
    end
]]
local getter_cache = {}
local setter_cache = {}
local function compile_normalized_property(field_path)
    local getter, setter = getter_cache[field_path], setter_cache[field_path]
    if not getter then
        getter = assert(loadstring(getter_template:format(field_path)))()
        getter_cache[field_path] = getter
        setter = assert(loadstring(setter_template:format(field_path)))()
        setter_cache[field_path] = setter
    end
    return getter, setter
end

function _M.compile_property(field_path)
    return compile_normalized_property(normalize_field_path(field_path))
end

local set

local function create()
    local o = {
        dirty = false, 
        _stage = {},
        _trace = {},
        _parent = false, 
    }
    return setmetatable(o, {
        __index = o._stage, 
        __newindex = set,
        
        __len = _M.len, 
        __pairs = _M.pairs, 
        __ipairs = _M.ipairs,
    })
end

local function mark_dirty(t)
    while t and not t.dirty do
        t.dirty = true
        t = t._parent
    end
end

set = function (t, k, v)
    local stage = t._stage
    local u = stage[k]
    if _M.is_traceable(v) then
        if _M.is(u) then
            for k in pairs(u._stage) do
                if v[k] == nil then
                    u[k] = nil
                end
            end
        else
            u = create()
            u._parent = t
            stage[k] = u
        end
        merge(u, v)
    else
        local trace = t._trace
        if trace[k] == nil then
            trace[k] = u == nil and null or u
        end
        stage[k] = v
        mark_dirty(t)
    end
end

function _M.is(t)
    local mt = getmetatable(t)
    return type(mt) == "table" and mt.__newindex == set
end

function _M.is_traceable(t)
    if type(t) ~= "table" then
        return false
    end
    local mt = getmetatable(t)
    return mt == nil or mt.__newindex == set
end
assert(not _M.is_traceable(_M.null))

function _M.new(t)
    local o = create()
    if t then
        merge(o, t)
    end
    return o
end

local k_stub = setmetatable({}, { __tostring = function () return "k_stub" end })
function _M.compile_map(src)
    local o = {}
    for i = 1, #src do
        local v = src[i]
        local argc = #v
        -- v = {argc, action, arg1, arg2, ..., argn}
        v = {argc, unpack(v)} -- copy

        for j = 1, argc - 1 do
            local k = j + 2
            local arg = normalize_field_path(v[k])
            v[k] = compile_normalized_property(arg)
            local p, c = nil, o
            for field in arg:gmatch("([^%[%]\'\"]+)") do
                field = tonumber(field) or field
                p, c = c, c[field]
                if not c then
                    c = {}
                    p[field] = c
                end
            end
            local stub = c[k_stub]
            if not stub then
                stub = {[1] = 1}
                c[k_stub] = stub
            end
            local n = stub[1] + 1
            stub[1] = n
            stub[n] = v
        end
    end
    return o
end

local function get_map_stub(map, k)
    local map_k = map[k]
    return map_k and map_k[k_stub]
end

local argv = {}
local function do_map(t, mappings, mapped)
    for i = 2, mappings[1] do
        local mapping = mappings[i]
        if not mapped[mapping] then
            mapped[mapping] = true
            local argc = mapping[1]        
            local argv = argv
            argv[1] = t
            for i = 2, argc do
                argv[i] = mapping[i + 1](t)
            end
            
            local action = mapping[2]
            action(unpack(argv, 1, argc))
        end
    end
end

local function diff(t, sub, newestversion, lastversion, map, mapped)
    if not sub.dirty then
        return 
    end

    local stage = sub._stage
    local trace = sub._trace

    local changed = false
    local keys = {}
    for k, u in pairs(trace) do
        local v = stage[k]
        if u == null then
            u = nil
        end
        if u ~= v then
            changed = true
            keys[k] = true
            if newestversion then
                newestversion[k] = v
            end
            if lastversion then
                lastversion[k] = u
            end

            if map then
                local stub = get_map_stub(map, k)
                if stub then
                    do_map(t, stub, mapped)
                end
            end
        end
    end
    for k, v in pairs(stage) do
        if _M.is(v) then
            local d, n, l = diff(t, v, 
                newestversion and {}, lastversion and {}, 
                map and map[k], mapped)
            if d then
                changed = true
                keys[k] = d
                if newestversion then
                    newestversion[k] = n
                end                
                if lastversion then
                    lastversion[k] = l
                end

                if map then
                    local stub = get_map_stub(map, k)
                    if stub then
                        do_map(t, stub, mapped)
                    end
                end
            end
        end
    end

    if not changed then
        return 
    end
    return keys, newestversion, lastversion
end

function _M.diff(t, newestversion, lastversion, map)
    if newestversion and lastversion == nil and map == nil then
        newestversion, lastversion, map = nil, nil, newestversion
    end
    
    local keys = diff(t, t, newestversion, lastversion, map, map and {}) or {}
    return keys, newestversion, lastversion
end

local function commit(t, sub, map, mapped)
    if not sub.dirty then
        return false
    end

    local stage = sub._stage
    local trace = sub._trace

    local committed = false
    for k, u in pairs(trace) do
        local v = stage[k]
        if u == null then
            u = nil
        end
        if u ~= v then
            trace[k] = nil
            committed = true
            
            if map then
                local stub = get_map_stub(map, k)
                if stub then
                    do_map(t, stub, mapped)
                end
            end
        end
    end
    for k, v in pairs(stage) do
        if _M.is(v) then
            if commit(t, v, map and map[k], mapped) then
                committed = true

                if map then
                    local stub = get_map_stub(map, k)
                    if stub then
                        do_map(t, stub, mapped)
                    end
                end
            end
        end
    end
    sub.dirty = false
    return committed
end

function _M.commit(t, map)
    commit(t, t, map, map and {})
end

local function do_maps(t, sub, map, mapped)
    for k, map_k in pairs(map) do
        local stub = map_k[k_stub]
        if stub then
            do_map(t, stub, mapped) 
        end
        
        local v = sub[k]
        if type(v) == "table" then
            do_maps(t, v, map_k, mapped)
        end
    end
end

function _M.map(t, map)
    do_maps(t, t, map, map and {})
end

local function forward_to(field, func)
    return function (t, ...)
        return func(t[field], ...)
    end
end


function _M.len(t)
    return #(t._stage)
end
_M.next = forward_to("_stage", next)
_M.pairs = forward_to("_stage", pairs)
_M.ipairs = forward_to("_stage", ipairs)
_M.unpack = forward_to("_stage", unpack)

return _M
local traceable = require("traceable")

describe("basic tests -", function()
    local match = require("luassert.match")

    local mt = {__tostring = function (t) return "object" end}
    local object = setmetatable({}, mt)
    local raw_data = {
        boolean_value = false, 
        number_value = 1, 
        string_value = "string", 
        list_value = {1, 2, 3}, 
        nested_table_value = {
            nested_table_value = {
                stub_value = true, 
            }, 
        },
        object_value = object, 
    }
    
    local data

    before_each(function()
        assert.is_truthy(traceable.is_traceable(raw_data))
        data = traceable.new(raw_data)
    end)

    after_each(function()
        data = nil
    end)

    local function dump(t)
        if not traceable.is(t) then
            return t
        end

        local raw_table = {}
        for k, v in traceable.pairs(t) do
            raw_table[k] = dump(v)
        end
        return raw_table
    end

    describe("assignment -", function()
        test("check type", function ()
            assert.is_truthy(traceable.is_traceable(raw_data))
            assert.is_falsy(traceable.is_traceable(object))
            assert.is_truthy(traceable.is(data))
        end)

        it("should be dirty before commit", function ()
            assert.is_truthy(data.dirty)
        end)

        it("should be same with raw_data before commit", function ()
            assert.are.same(raw_data, dump(data))
        end)

        test("sub table should be convert to traceable", function ()
            assert.are_not.equal(raw_data.list_value, data.list_value)
            assert.is_truthy(traceable.is(data.list_value))

            assert.are_not.equal(raw_data.nested_table_value, data.nested_table_value)
            assert.is_truthy(traceable.is(data.nested_table_value))

            assert.are_not.equal(raw_data.nested_table_value.nested_table_value, data.nested_table_value.nested_table_value)
            assert.is_truthy(traceable.is(data.nested_table_value.nested_table_value))
        end)

        test("but sub table with metatable should not be convert to traceable", function ()
            assert.are.equal(raw_data.object_value, data.object_value)
            assert.is_falsy(traceable.is(data.object_value))
        end)

        it("should be same with raw_data after commit", function ()
            traceable.commit(data)
            assert.are.same(raw_data, dump(data))
        end)

        it("should not be dirty after commit", function ()
            traceable.commit(data)
            assert.is_falsy(data.dirty)
        end)
    end)

    describe("table operations -", function()
        test("len", function ()
            assert.are.equal(#raw_data.list_value, traceable.len(data.list_value))
        end)

        test("next", function ()
            for k, v in traceable.next, data do
                assert.are.equal(v, data[k])
            end
        end)

        test("pairs", function ()
            for k, v in traceable.pairs(data) do
                assert.are.equal(v, data[k])
            end
        end)

        test("ipairs", function ()
            for i, v in traceable.ipairs(data.list_value) do
                assert.are.equal(v, data.list_value[i])
            end
        end)

        test("unpack", function ()
            assert.are.same(raw_data.list_value, {traceable.unpack(data.list_value)})
        end)
    end)

    describe("add/remove field -", function()
        local new_fields = {
            new_boolean_value = false, 
            new_number_value = 1, 
            new_string_value = "string",
            new_list_value = {1, 2, 3}, 
            new_nested_table_value = {
                nested_table_value = {
                    stub_table = true, 
                }, 
            },
            new_object_value = setmetatable({}, mt)
        }

        local removed_fields = {
            boolean_value = true, 
            number_value = true, 
            string_value = true, 
            nested_table_value = true, 
            object_value = true
        }

        before_each(function ()
            traceable.commit(data)
            for k, v in pairs(new_fields) do
                data[k] = v
            end
            for k in pairs(removed_fields) do
                data[k] = nil
            end
        end)

        it("should have new fields before commit", function ()
            for k, v in pairs(new_fields) do
                assert.are.same(v, dump(data[k]))
            end
        end)

        it("should not have removed fields before commit", function ()
            for k in pairs(removed_fields) do
                assert.is_nil(data[k])
            end
        end)

        test("diff", function ()
            local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})

            assert.is_truthy(has_changed)
            
            for k, v in pairs(new_fields) do
                assert.is_truthy(changed[k])
                changed[k] = nil
                assert.are.same(v, dump(newestversion[k]))
            end
            
            for k in pairs(removed_fields) do
                assert.is_truthy(changed[k])
                changed[k] = nil
                assert.are.same(raw_data[k], dump(lastversion[k]))
            end

            assert.are.same({}, changed)
        end)

        it("should have new fields after commit", function ()
            traceable.commit(data)
            for k, v in pairs(new_fields) do
                assert.are.same(v, dump(data[k]))
            end
        end)

        it("should not have removed fields after commit", function ()
            traceable.commit(data)
            for k in pairs(removed_fields) do
                assert.is_nil(data[k])
            end
        end)
    end)
    
    describe("modify field -", function()
        local modified_fields = {
            boolean_value = true, 
            number_value = 2, 
            string_value = "another string", 
            list_value = {1, 2, 2, 1}, 
            nested_table_value = {
                new_stub_value = true,
                new_nested_table_value = {
                    new_stub_value = true, 
                }, 
                nested_table_value = {
                    stub_value = false,
                }, 
            },
            object_value = setmetatable({}, mt)
        }

        before_each(function ()
            traceable.commit(data)
            for k, v in pairs(modified_fields) do
                data[k] = v
            end
        end)

        test("lua table without metatable should be cloned including being assigned", function ()
            for k, v in pairs(modified_fields) do
                if type(v) == "table" and getmetatable(v) == nil then
                    assert.are_not.equals(v, data[k])
                end
            end
        end)

        it("should be modified as expected before commit", function ()
            for k, v in pairs(modified_fields) do
                assert.are.same(v, dump(data[k]))
            end
        end)

        it("should be modified as expected after commit", function ()
            traceable.commit(data)
            for k, v in pairs(modified_fields) do
                assert.are.same(v, dump(data[k]))
            end
        end)

        describe("test diff -", function ()
            test("diff", function ()
                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
    
                assert.is_truthy(has_changed)
                
                -- special cases
                -- list_value[1] is not changed, so it will not exist in diff results
                assert.is_nil(changed.list_value[1])
                newestversion.list_value[1] = data.list_value[1]
                lastversion.list_value[1] = data.list_value[1]
    
                -- list_value[2] is not changed, so it will not exist in diff results
                assert.is_nil(changed.list_value[2])
                newestversion.list_value[2] = data.list_value[2]
                lastversion.list_value[2] = data.list_value[2]
    
                -- data.nested_table_value.new_nested_table_value is a new table value with contents,
                -- so changed.nested_table_value.new_nested_table_value.new_stub_value will be true and
                -- lastversion.changed.nested_table_value.new_nested_table_value will be a table with nothing (contents are all nil)
                assert.is_truthy(changed.nested_table_value.new_nested_table_value.new_stub_value)
                assert.are.same({}, lastversion.nested_table_value.new_nested_table_value)
                lastversion.nested_table_value.new_nested_table_value = nil
    
                for k, v in pairs(modified_fields) do
                    assert.is_truthy(changed[k])
                    assert.are.same(v, dump(newestversion[k]))
                    assert.are.same(raw_data[k], dump(lastversion[k]))
                end
            end)
    
            test("set_ignored", function ()
                -- ignore
                traceable.set_ignored(data.nested_table_value, true)
                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
                assert.is_nil(changed.nested_table_value)

                -- cancel ignore
                traceable.set_ignored(data.nested_table_value, false)
                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
                assert.is_truthy(changed.nested_table_value.new_nested_table_value.new_stub_value)
                assert.are.same(modified_fields.nested_table_value, dump(newestversion.nested_table_value))
            end)
    
            test("set_opaque", function ()
                traceable.set_opaque(data.nested_table_value, true)
                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
                assert.is_truthy(changed.nested_table_value)
                assert.is_nil(newestversion.nested_table_value)
                assert.is_nil(lastversion.nested_table_value)

                traceable.set_opaque(data.nested_table_value, false)
                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
                assert.is_truthy(changed.nested_table_value)
                assert.is_truthy(newestversion.nested_table_value)
                assert.is_truthy(lastversion.nested_table_value)
            end)
    
            test("mark_changed", function ()
                traceable.commit(data)

                traceable.mark_changed(data, "object_value")
                assert.is_truthy(data.dirty)

                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
                assert.are.same({object_value = true}, changed)
                assert.are.same({object_value = modified_fields.object_value}, newestversion)
                assert.are.same({object_value = modified_fields.object_value}, lastversion)
            end)
        end)
    
        describe("test mapping -", function()
            local function create_spy(tag)
                return spy.new(function (t, ...)
                    -- print(tag, t, ...)
                end)
            end
    
            local map
            
            before_each(function ()
                map = {
                    { create_spy(1), "boolean_value" }, 
                    { create_spy(2), "number_value" }, 
                    { create_spy(3), "string_value" }, 
                    { create_spy(4), "list_value" }, 
                    { create_spy(5), "list_value[3]" }, 
                    { create_spy(6), "list_value[4]" }, 
                    { create_spy(7), "nested_table_value" }, 
                    { create_spy(8), "nested_table_value.new_stub_value" }, 
                    { create_spy(9), "nested_table_value.new_nested_table_value" }, 
                    { create_spy(10), "nested_table_value.new_nested_table_value.new_stub_value" }, 
                    { create_spy(11), "nested_table_value.nested_table_value" }, 
                    { create_spy(12), "nested_table_value.nested_table_value.stub_value" }, 
                    { create_spy(13), "object_value" }, 
        
                    { create_spy(14), "boolean_value", "number_value" },
                    { create_spy(15), "string_value", "list_value" },
                    { create_spy(16), "list_value", "list_value[3]", "list_value[4]" },
                    { create_spy(17), "boolean_value", "nested_table_value.new_stub_value" },
                    { create_spy(18), "object_value", "nested_table_value.new_nested_table_value.new_stub_value" },
                }
            end)
    
            test("commit with mapping", function ()
                traceable.commit(data, traceable.compile_map(map))
    
                for i, v in ipairs(map) do
                    local action = v[1]
                    local args = {match.is_ref(data), unpack(v, 2)}
                    for i = 2, #args do
                        local arg = traceable.compile_property(args[i])(data)
                        if type(arg) == "table" then
                            arg = match.is_ref(arg)
                        end
                        args[i] = arg
                    end
                    assert.spy(action).was_called()
                    assert.spy(action).was_called_with(unpack(args))
                end
            end)
    
            test("diff with mapping", function ()
                traceable.diff(data, traceable.compile_map(map))
    
                for i, v in ipairs(map) do
                    local action = v[1]
                    local args = {match.is_ref(data), unpack(v, 2)}
                    for i = 2, #args do
                        local arg = traceable.compile_property(args[i])(data)
                        if type(arg) == "table" then
                            arg = match.is_ref(arg)
                        end
                        args[i] = arg
                    end
                    assert.spy(action).was_called()
                    assert.spy(action).was_called_with(unpack(args))
                end
            end)
    
            test("mapping on whole data", function ()
                traceable.map(data, traceable.compile_map(map))
    
                for i, v in ipairs(map) do
                    local action = v[1]
                    local args = {match.is_ref(data), unpack(v, 2)}
                    for i = 2, #args do
                        local arg = traceable.compile_property(args[i])(data)
                        if type(arg) == "table" then
                            arg = match.is_ref(arg)
                        end
                        args[i] = arg
                    end
                    assert.spy(action).was_called()
                    assert.spy(action).was_called_with(unpack(args))
                end
            end)
    
            test("mapping on diff", function ()
                local has_changed, changed, newestversion, lastversion = traceable.diff(data, {}, {}, {})
                traceable.map(newestversion, traceable.compile_map(map))
    
                for i, v in ipairs(map) do
                    local action = v[1]
                    local args = {match.is_ref(newestversion), unpack(v, 2)}
                    for i = 2, #args do
                        local arg = traceable.compile_property(args[i])(newestversion)
                        if type(arg) == "table" then
                            arg = match.is_ref(arg)
                        end
                        args[i] = arg
                    end
                    assert.spy(action).was_called()
                    assert.spy(action).was_called_with(unpack(args))
                end
            end)
    
            test("set_ignored", function ()
                traceable.set_ignored(data.nested_table_value, true)
                traceable.commit(data, traceable.compile_map(map))
                assert.is_truthy(data.nested_table_value.dirty)
    
                for i = 7, 12 do
                    local v = map[i]
                    local action = v[1]
                    assert.spy(action).was_not_called()
                end
                
                traceable.set_ignored(data.nested_table_value, false)
                assert.is_truthy(data.dirty)
                traceable.commit(data, traceable.compile_map(map))
                assert.is_falsy(data.nested_table_value.dirty)
    
                for i, v in ipairs(map) do
                    local action = v[1]
                    local args = {match.is_ref(data), unpack(v, 2)}
                    for i = 2, #args do
                        local arg = traceable.compile_property(args[i])(data)
                        if type(arg) == "table" then
                            arg = match.is_ref(arg)
                        end
                        args[i] = arg
                    end
                    if i < 17 then
                        assert.spy(action).was_called(1)
                    else
                        assert.spy(action).was_called(2)
                    end
                    assert.spy(action).was_called_with(unpack(args))
                end
            end)
    
            test("set_opaque", function ()
                traceable.set_opaque(data.nested_table_value, true)
                traceable.commit(data, traceable.compile_map(map))
                assert.is_falsy(data.nested_table_value.dirty)
    
                for i = 8, 12 do
                    local v = map[i]
                    local action = v[1]
                    assert.spy(action).was_not_called()
                end
            end)
    
            test("mark_changed", function ()
                traceable.commit(data, traceable.compile_map(map))

                traceable.mark_changed(data, "object_value")
                assert.is_truthy(data.dirty)

                traceable.commit(data, traceable.compile_map(map))
                local v = map[13]
                local action = v[1]
                local args = {match.is_ref(data), unpack(v, 2)}
                for i = 2, #args do
                    local arg = traceable.compile_property(args[i])(data)
                    if type(arg) == "table" then
                        arg = match.is_ref(arg)
                    end
                    args[i] = arg
                end
                assert.spy(action).was_called(2)
                assert.spy(action).was_called_with(unpack(args))
            end)
        end)
    end)
    
    describe("assgin same values -", function()
        local modified_fields = {
            boolean_value = false, 
            number_value = 1, 
            string_value = "string", 
            list_value = {1, 2, 3}, 
            nested_table_value = {
                nested_table_value = {
                    stub_value = true, 
                }, 
            },
            object_value = object, 
        }

        before_each(function ()
            traceable.commit(data)
            for k, v in pairs(modified_fields) do
                data[k] = v
            end
        end)

        it("should has no diff", function ()
            local has_changed = traceable.diff(data)
            assert.are.is_falsy(has_changed)
        end)

    end)
end)
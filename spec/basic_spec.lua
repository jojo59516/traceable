local traceable = require("traceable")

describe("basic tests -", function()
    local match = require("luassert.match")

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
            assert.is_truthy(traceable.is(data))
        end)

        it("should be dirty before commit", function ()
            assert.is_truthy(data.dirty)
        end)

        it("should be same with raw_data before commit", function ()
            assert.are.same(raw_data, dump(data))
        end)

        test("sub table should be convert to traceable", function ()
            assert.is_truthy(traceable.is(data.list_value))
            assert.is_truthy(traceable.is(data.nested_table_value))
            assert.is_truthy(traceable.is(data.nested_table_value.nested_table_value))
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
        }

        local removed_fields = {
            boolean_value = true, 
            number_value = true, 
            string_value = true, 
            nested_table_value = true, 
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
            local keys, newestversion, lastversion = traceable.diff(data, {}, {})
            
            for k, v in pairs(new_fields) do
                assert.is_truthy(keys[k])
                keys[k] = nil
                assert.are.same(v, dump(newestversion[k]))
            end
            
            for k in pairs(removed_fields) do
                assert.is_truthy(keys[k])
                keys[k] = nil
                assert.are.same(raw_data[k], dump(lastversion[k]))
            end

            assert.are.same({}, keys)
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
        }

        before_each(function ()
            traceable.commit(data)
            for k, v in pairs(modified_fields) do
                data[k] = v
            end
        end)

        test("lua table without metatable should be cloned including being assigned", function ()
            for k, v in pairs(modified_fields) do
                if type(v) == "table" then
                    assert.are_not.equals(v, data[k])
                end
            end
        end)

        it("should be modified as expected before commit", function ()
            for k, v in pairs(modified_fields) do
                assert.are.same(v, dump(data[k]))
            end
        end)

        test("diff", function ()
            local keys, newestversion, lastversion = traceable.diff(data, {}, {})
            
            -- special cases
            -- list_value[1] is not changed, so it will not exist in diff results
            assert.is_nil(keys.list_value[1])
            newestversion.list_value[1] = data.list_value[1]
            lastversion.list_value[1] = data.list_value[1]

            -- list_value[2] is not changed, so it will not exist in diff results
            assert.is_nil(keys.list_value[2])
            newestversion.list_value[2] = data.list_value[2]
            lastversion.list_value[2] = data.list_value[2]

            -- data.nested_table_value.new_nested_table_value is a new table value with contents,
            -- so keys.nested_table_value.new_nested_table_value.new_stub_value will be true and
            -- lastversion.keys.nested_table_value.new_nested_table_value will be a table with nothing (contents are all nil)
            assert.is_truthy(keys.nested_table_value.new_nested_table_value.new_stub_value)
            assert.are.same({}, lastversion.nested_table_value.new_nested_table_value)
            lastversion.nested_table_value.new_nested_table_value = nil

            for k, v in pairs(modified_fields) do
                assert.is_truthy(keys[k])
                assert.are.same(v, dump(newestversion[k]))
                assert.are.same(raw_data[k], dump(lastversion[k]))
            end
        end)

        it("should be modified as expected after commit", function ()
            traceable.commit(data)
            for k, v in pairs(modified_fields) do
                assert.are.same(v, dump(data[k]))
            end
        end)
    end)
    
    describe("test mapping -", function()
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
        }

        local function create_spy(name)
            return spy.new(function (t, ...)
                -- print(name, t, ...)
            end)
        end

        local map = {
            { create_spy(""), "boolean_value" }, 
            { create_spy(""), "number_value" }, 
            { create_spy(""), "string_value" }, 
            { create_spy(""), "list_value" }, 
            { create_spy(""), "nested_table_value" }, 
            { create_spy(""), "list_value[3]" }, 
            { create_spy(""), "list_value[4]" }, 
            { create_spy(""), "nested_table_value.new_stub_value" }, 
            { create_spy(""), "nested_table_value.new_nested_table_value" }, 
            { create_spy(""), "nested_table_value.new_nested_table_value.new_stub_value" }, 
            { create_spy(""), "nested_table_value.nested_table_value" }, 
            { create_spy(""), "nested_table_value.nested_table_value.stub_value" }, 

            { create_spy(""), "boolean_value", "number_value" },
            { create_spy(""), "string_value", "list_value" },
            { create_spy(""), "list_value", "list_value[3]", "list_value[4]" },
            { create_spy(""), "boolean_value", "nested_table_value.new_stub_value" },
            { create_spy(""), "number_value", "nested_table_value.new_nested_table_value.new_stub_value" },
        }
        
        before_each(function ()
            traceable.commit(data)
            for k, v in pairs(modified_fields) do
                data[k] = v
            end
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
    end)
end)
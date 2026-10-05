local class = require("ito.class")
local Tuple = require("ito.runtime.identity").Tuple

local Node = class()

function Node:init(kind)
    self.kind = kind
    self.children = {}
    self.keyed = {}
    self.states = {}
    self.memo = {}
    self.hook = 0
    self.seen = 0
end

function Node:slot(key)
    if getmetatable(key) ~= Tuple then
        return key
    end
    self.tuples = self.tuples or {}
    self.tuples[key.n] = self.tuples[key.n] or {}
    local level = self.tuples[key.n]
    for index = 1, key.n - 1 do
        level[key[index]] = level[key[index]] or {}
        level = level[key[index]]
    end
    local token = level[key[key.n]]
    if not token then
        token = key
        level[key[key.n]] = token
    end
    return token
end

function Node:forget(token)
    local path = { self.tuples[token.n] }
    for index = 1, token.n - 1 do
        path[index + 1] = path[index][token[index]]
    end
    path[token.n][token[token.n]] = nil
    for index = token.n, 2, -1 do
        if next(path[index]) ~= nil then
            return
        end
        path[index - 1][token[index - 1]] = nil
    end
end

function Node:sweep(generation)
    for index, child in pairs(self.children) do
        if child.seen ~= generation then
            self.children[index] = nil
        end
    end
    for key, child in pairs(self.keyed) do
        if child.seen ~= generation then
            self.keyed[key] = nil
            if getmetatable(key) == Tuple then
                self:forget(key)
            end
        end
    end
end

return Node

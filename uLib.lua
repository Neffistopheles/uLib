--[[
  uLib.lua - "Micro Lib" for World of Warcraft 1.12 client
  
  A tiny addon stub and library providing most of the basic functionality
  for addon boilerplate and quick prototyping. Comparable in features to the
  core of projects like Ace, but significantly smaller and simpler.
  
  Note that the below code is written against Lua 5.0, for WoW 1.12, not 5.1+.
  
  Copyright (c) 2018, Anthony Eadicicco. All Rights Reserved.
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
--]]


local _G = getfenv(0)


-- Lib
local name = 'uLib'
local version = 0001

local lib = _G[name] or {}
if (lib.version or 0) >= version then return end
lib.name = name
lib.version = version
_G[name] = lib

lib.__handler = lib.__handler or CreateFrame('Frame')


-- Addon registry
lib.__index = lib
function lib:newaddon(name, mod)
  mod = mod or {}
  mod.name       = name
  mod.version    = GetAddOnMetadata(name, 'Version') or 0
  mod.path       = string.format([[Interface\AddOns\%s\]], name)
  mod.debuglevel = 0
  _G[name] = setmetatable(mod, lib)
  return mod
end


-- I/O
function lib:print(msg, ...)
  msg = '|cffff7fff%s|r: ' .. msg
  msg = string.format(msg, self.name, self.tostringall(unpack(arg)))
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

function lib:debug(lvl, msg, ...)
  if (self.debuglevel or 0) < lvl then return end
  msg = '[Debug] ' .. msg
  self:print(msg, unpack(arg))
end


-- Aux lib
function lib.tostringall(...)
  for i = 1, arg.n do
    arg[i] = tostring(arg[i])
  end
  return unpack(arg)
end

function lib.softerror(msg)
  DEFAULT_CHAT_FRAME:AddMessage('|cffff7f7fError|r: %s', msg)
end


-- Timers
do
  local timers  = lib.__timers or {}; lib.__timers = timers
  local tstate  = lib.__tstate or {
    lock = false,
    append = {},
  }; lib.__tstate = tstate
  local append = tstate.append
  local handler = lib.__handler
  
  handler:SetScript('OnUpdate', function()
    local now = GetTime()
    tstate.lock = true
    for callback, data in next, timers do
      local fireat = data.fireat
      local rpt    = data.rpt
      if fireat <= now then
        local succ, err = pcall(callback)
        if not succ then lib.softerror(err)  end
        if rpt then
          data.fireat = fireat + rpt
        else
          timers[callback] = nil
        end
      end
    end
    tstate.lock = false
    for callback, data in append do
      timers[callback] = data
      append[callback] = nil
    end
    if next(timers) == nil then handler:Hide() end
  end)
  if next(timers) == nil and next(append) == nil then
    handler:Hide()
  end
  
  function lib:timerreg(delay, rpt, callback)
    assert(type(delay) == 'number', 'bad argument #1')
    assert(type(callback) == 'function', 'bad argument #2')
    local data = timers[callback] or append[callback]
    if data then
      -- Subsequent calls can be used to adjust the reiterating delay of an
      -- existing timer, but cannot affect how long the next invocation will
      -- take.
      data.rpt = rpt and delay
      return
    end
    data = {
      fireat = GetTime() + delay,
      rpt    = rpt and delay or nil,
    }
    if tstate.lock then
      append[callback] = data
    else
      timers[callback] = data
    end
    handler:Show()
  end
  
  function lib:timerunreg(callback)
    assert(type(callback) == 'function', 'bad argument #1')
    timers[callback] = nil
    append[callback] = nil
    if next(timers) == nil and next(append) == nil then
      handler:Hide()
    end
  end
end


-- Events
do
  local events  = lib.__events or {}; lib.__events = events
  local equeues = lib.__equeues or {}; lib.__equeues = equeues
  local elocks  = lib.__elocks or {}; lib.__elocks = elocks
  local handler = lib.__handler
  
  handler:SetScript('OnEvent',
    function(event, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
      -- Don't use `...`. This is potentially extremely spammy during combat,
      -- and construction of `arg` involves a lot of extra garbage. As of
      -- 1.12.1, no event throws more than 12 arguments.
      local ev, eq = events[event], equeues[event]
      if not ev or elocks[event] then return end
      elocks[event] = true
      for callback in next, ev do
        local succ, err = pcall(callback, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
        if not succ then lib.softerror(err) end
      end
      elocks[event] = nil
      for callback in next, eq do
        eq[callback] = nil
        ev[callback] = true
      end
    end
  )
  
  function lib:eventreg(event, callback)
    assert(type(event) == 'string', 'bad argument #1')
    assert(type(callback) == 'function', 'bad argument #1')
    local ev, eq = events[event], equeues[event]
    if not ev then
      ev, eq = {}, {}
      events[event], equeues[event] = ev, eq
      handler:RegisterEvent(event)
    end
    if elocks[event] then
      eq[callback] = true
    else
      ev[callback] = true
    end
    return callback
  end
  
  function lib:eventunreg(event, callback)
    assert(type(event) == 'string', 'bad argument #1')
    assert(type(callback) == 'function', 'bad argument #1')
    local ev, eq = events[event], equeues[event]
    if ev then
      ev[callback] = nil
      eq[callback] = nil
      if next(ev) == nil and next(eq) == nil then
        events[event], qeueues[event] = nil, nil
        handler:UnregisterEvent(event)
      end
    end
    return callback
  end
  
  function lib:eventoneshot(event, callback)
    assert(type(event) == 'string', 'bad argument #1')
    assert(type(callback) == 'function', 'bad argument #1')
    local f
    f = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
      self:eventunreg(event, f)
      callback(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
    end
    return self:eventreg(event, f)
  end
end

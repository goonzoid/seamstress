-- params menu

--[[
  based on norns' params menu
  norns params menu first committed by @artfwo April 8, 2018
  reimagined for seamstress by @dndrks June 26, 2023
]]

local keycode = require("keycodes")

local mEDIT = 1
local mMAP = 2
local mTEXT = 3
local mPSET = 4
local mPSETSAVE = 5
local mPSETEDIT = 6

local textentry = {}

textentry.enter = function(callback, default, heading, check)
  textentry.txt = default or ""
  textentry.heading = heading or ""
  textentry.callback = callback
  textentry.check = check
  textentry.warn = check ~= nil and check(textentry.txt) or nil
  textentry.active = true
end

textentry.exit = function()
  if textentry.txt then
    textentry.callback(textentry.txt)
  else
    textentry.callback(nil)
  end
  textentry.active = false
end

local m = {
  pos = 0,
  oldpos = 0,
  group = false,
  groupid = 0,
  alt = false,
  mode = mEDIT,
  mode_pos = 1,
  map = false,
  midi_learn = { pos = 0, state = false },
  dev = 1,
  ch = 1,
  cc = 100,
  pm,
  ps_pos = 0,
  ps_n = 0,
  ps_action = 1,
  ps_last = 0,
  dir_prev = nil,
  highlightColors = { r = 0, g = 140, b = 140 },
}

local page
local pset = {}

-- called from menu on script reset
m.reset = function()
  page = nil
  m.pos = 0
  m.group = false
  m.ps_pos = 0
  m.ps_n = 0
  m.ps_action = 1
  m.mode = mEDIT
end

local function build_page()
  page = {}
  local i = 1
  repeat
    if params:visible(i) then
      table.insert(page, i)
    end
    if params:t(i) == params.tGROUP then
      i = i + params:get(i) + 1
    else
      i = i + 1
    end
  until i > params.count
end

local function build_sub(sub)
  page = {}
  for i = 1, params:get(sub) do
    if params:visible(i + sub) then
      table.insert(page, i + sub)
    end
  end
end

function init_pset()
  print("scanning PSETs...")
  local psets = io.popen("ls -1 " .. seamstress.state.data .. "*.pset | sort")
  pset = {}
  m.ps_n = 0
  for filename in psets:lines() do
    local n = tonumber(filename:match("(%d+).pset$"))
    if not n then
      n = 1
    end
    local name = seamstress.state.name
    local f = io.open(filename, "r")
    io.input(filename)
    local line = io.read("*line")
    if util.string_starts(line, "-- ") then
      name = string.sub(line, 4, -1)
    end
    io.close(f)
    pset[n] = { file = filename, name = name }
    m.ps_n = math.max(n, m.ps_n)
  end
  psets:close()
  m.ps_n = m.ps_n + 1
  m.redraw()
end

local function write_pset_last(x)
  local file = seamstress.state.data .. "pset-last.txt"
  local f = io.open(file, "w")
  io.output(f)
  io.write(x)
  io.close(f)
  seamstress.state.pset_last = x
end

local function write_pset(name)
  if name then
    local i = m.ps_pos + 1
    if name == "" then
      name = params.name
    end
    params:write(i, name)
    m.ps_last = i
    write_pset_last(i) -- save last pset loaded
    init_pset()
    pmap.write() -- write parameter map too
  end
end

m.key = function(char, modifiers, is_repeat, state)
  -- encapsulates both encoder + key interactions from norns...

  -- hotkey UI flips:
  if not textentry.active then
    if #modifiers == 1 and modifiers[1] == "shift" then
      if char == "m" and state == 1 then
        m.mode = m.mode == mEDIT and mMAP or mEDIT
        if m.group then
          build_sub(m.groupid)
        else
          build_page()
        end
      elseif char == "p" and state == 1 then
        m.mode = m.mode == mEDIT and mPSET or mEDIT
        init_pset()
      end
    end
  end

  -- navigation:
  if m.mode == mEDIT or m.mode == mMAP then
    local i = page[m.pos + 1]
    local t = params:t(i)
    if (char.name == "up" or char.name == "down") and state == 1 then
      if tab.contains(modifiers, "alt") then
        -- jump
        local d = char.name == "up" and -1 or 1
        local i = m.pos + 1
        repeat
          i = i + d
          if i > #page then
            i = 1
          end
          if i < 1 then
            i = #page
          end
        until params:t(page[i]) == params.tSEPARATOR or i == 1
        m.pos = i - 1
        m.midi_learn.pos = m.pos
      else
        -- delta 1
        local d = char.name == "up" and -1 or 1
        local prev = m.pos
        m.pos = util.clamp(m.pos + d, 0, #page - 1)
        m.midi_learn.pos = m.pos
        m.midi_learn.state = false
        if m.pos ~= prev then
          m.redraw()
        end
      end
    elseif (char.name == "right" or char.name == "left") and state == 1 then
      -- adjust value
      if params.count > 0 then
        local d = char.name == "left" and -1 or 1
        local dx = m.fine and (d / 20) or (m.coarse and d * 10 or d)
        params:delta(page[m.pos + 1], dx)
      end
    elseif char.name == "return" then
      if state == 1 then
        -- enter group
        if t == params.tGROUP then
          build_sub(i)
          m.group = true
          m.groupid = i
          m.groupname = params:string(i)
          m.oldpos = m.pos
          m.pos = 0
        -- jump separator
        elseif t == params.tSEPARATOR then
          local n = m.pos + 1
          repeat
            n = n + 1
            if n > #page then
              n = 1
            end
          until params:t(page[n]) == params.tSEPARATOR
          m.pos = n - 1
        -- enter text
        elseif t == params.tTEXT then
          if params:lookup_param(i).locked == false then
            if m.mode == mEDIT then
              m.mode = mTEXT
              textentry.enter(m.newtext, params:get(i), "PARAM: " .. params:get_name(i), params:lookup_param(i).check)
            end
          end
        -- midi learn
        elseif m.mode == mMAP and params:get_allow_pmap(i) then
          local n = params:get_id(i)
          local pm = params:lookup_param(n).midi_mapping

          m.midi_learn.pos = m.pos
          if pm.dev == nil then
            m.midi_learn.state = not m.midi_learn.state
            if m.midi_learn.state then
              pmap.new(n)
              pm = params:lookup_param(n).midi_mapping
            end
          else
            m.midi_learn.state = false
          end
        end
      end
    elseif char.name == "rshift" then
      m.fine = state == 1
    elseif char.name == "ralt" then
      m.coarse = state == 1
    elseif char.name == "backspace" then
      if tab.contains(modifiers, "shift") and state == 1 then
        if m.mode == mMAP then
          pmap.remove(i)
        end
      elseif state == 1 then
        if m.group == true then
          m.group = false
          build_page()
          m.pos = m.oldpos
        end
      end
    end
  elseif m.mode == mTEXT or m.mode == mPSETSAVE then
    if char.name == "escape" and state == 1 then
      m.mode = m.mode == mTEXT and mEDIT or mPSET
    elseif char.name == "backspace" and state == 1 then
      textentry.txt = string.sub(textentry.txt, 0, -2)
      if textentry.check then
        textentry.warn = textentry.check(textentry.txt)
      end
    elseif char.name == "return" and state == 1 then
      textentry.exit()
      m.mode = m.mode == mTEXT and mEDIT or mPSET
    elseif type(char) == "string" and state == 1 then
      if tab.contains(modifiers, "shift") then
        textentry.txt = textentry.txt .. keycode.shifted[char]
      else
        textentry.txt = textentry.txt .. char
      end
      if textentry.check then
        textentry.warn = textentry.check(textentry.txt)
      end
    end
  elseif m.mode == mPSET then
    if (char.name == "up" or char.name == "down") and state == 1 then
      if tab.contains(modifiers, "alt") then
        m.ps_pos = util.clamp(m.ps_pos + (char.name == "up" and -8 or 8), 0, 98)
      else
        m.ps_pos = util.clamp(m.ps_pos + (char.name == "up" and -1 or 1), 0, 98)
      end
    elseif (char.name == "left" or char.name == "right") and state == 1 then
      m.ps_action = util.clamp(m.ps_action + (char.name == "left" and -1 or 1), 1, 3)
    elseif char.name == "return" and state == 1 then
      if m.ps_action == 1 then
        m.mode = mPSETSAVE
        local name = pset[m.ps_pos + 1] and pset[m.ps_pos + 1].name or (seamstress.state.name .. m.ps_pos + 1)
        textentry.enter(write_pset, name, "PSET NAME: " .. (m.ps_pos + 1))
      elseif m.ps_action == 3 then
        if pset[m.ps_pos + 1] then
          m.mode = mPSETEDIT
        end
      else
        local i = m.ps_pos + 1
        if pset[i] then
          params:read(i)
          m.ps_last = i
          write_pset_last(i) -- save last pset loaded
        end
      end
    end
  elseif m.mode == mPSETEDIT then
    if char.name == "return" and state == 1 then
      m.mode = mPSET
      params:delete(pset[m.ps_pos + 1].file, pset[m.ps_pos + 1].name, string.format("%02d", m.ps_pos + 1))
      init_pset()
    elseif (char.name == "escape" or char.name == "backspace") and state == 1 then
      m.mode = mPSET
    end
  end
  m.redraw()
end

m.newtext = function(txt)
  if txt ~= "cancel" then
    params:set(page[m.pos + 1], txt)
    m.redraw()
  end
end

local function draw_separator(param_name)
  if screen.get_text_size(param_name) > 180 then
    param_name = util.trim_string_to_width(param_name, 180)
  end
  screen.text(param_name)
  screen.move_rel(0, 8)
  screen.line_rel(180, 0)
  screen.move_rel(0, -8)
end

local function draw_text(param_name, val)
  if screen.get_text_size(param_name) > 100 then
    param_name = util.trim_string_to_width(param_name, 100)
  end
  screen.text(param_name)
  screen.move_rel(127, 0)
  local val_spacing = screen.get_text_size(val)
  if val_spacing > 90 then
    val = util.trim_string_to_width(val, 93)
  end
  screen.text(val)
  screen.move_rel(-127, 0)
end

local function draw_param(param_name, val)
  if screen.get_text_size(param_name) > 100 then
    param_name = util.trim_string_to_width(param_name, 100)
  end
  screen.text(param_name)
  screen.move_rel(127, 0)
  screen.text(val)
  screen.move_rel(-127, 0)
end

m.redraw = function()
  _seamstress.screen_set(2)
  screen.clear()

  if m.mode == mEDIT then
    local n = "PARAMETERS"
    if m.group then
      n = n .. " / " .. m.groupname
    end
    screen.color(130, 140, 140, 255)
    screen.move(10, 10)
    screen.text(n)
    screen.move_rel(0, 20)
    for i = 1, 20 do
      if (i > 1 - m.pos) and (i < #page - m.pos + 2) then
        if i == 2 then
          screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b, 255)
        else
          screen.color(130, 140, 140, 255)
        end
        local p = page[i + m.pos - 1]
        local t = params:t(p)
        local param_name = params:get_name(p)
        screen.move_rel(0, 10)
        if t == params.tSEPARATOR then
          draw_separator(param_name)
        elseif t == params.tGROUP then
          screen.text(param_name .. " >")
        elseif t == params.tTEXT then
          draw_text(param_name, params:string(p))
        else
          draw_param(param_name, params:string(p, params:is_number(p) and 1 or 0.001))
        end
      end
    end
  elseif m.mode == mMAP then
    local n = "PARAMETERS: MAPPING"
    if m.group then
      n = n .. " / " .. m.groupname
    end
    screen.color(130, 140, 140, 255)
    screen.move(10, 10)
    screen.text(n)
    screen.move_rel(0, 20)
    for i = 1, 20 do
      if (i > 1 - m.pos) and (i < #page - m.pos + 2) then
        if i == 2 then
          screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
        else
          screen.color(130, 140, 140, 255)
        end
        local p = page[i + m.pos - 1]
        local t = params:t(p)
        local n = params:get_name(p)
        local id = params:get_id(p)
        screen.move_rel(0, 10)
        if t == params.tSEPARATOR then
          draw_separator(n)
        elseif t == params.tGROUP then
          screen.text(n .. " >")
        elseif t == params.tTEXT then
          draw_text(id, params:string(p))
        else
          screen.text(id)
          screen.move_rel(127, 0)
          if params:get_allow_pmap(id) then
            local pm = params:lookup_param(id).midi_mapping
            if pm.dev then
              screen.text("CC:" .. pm.cc .. " | CH:" .. pm.ch .. " | DEV:" .. pm.dev)
            elseif m.midi_learn.state and i == 2 then
              screen.text("[learning]")
            else
              screen.text("-")
            end
          end
          screen.move_rel(-127, 0)
        end
      end
    end
  elseif m.mode == mTEXT then
    screen.color(3, 138, 255)
    screen.move(10, 100)
    screen.text("escape: cancel")
    screen.move(10, 110)
    screen.text("enter: commit")
    screen.move(10, 10)
    screen.color(130, 140, 140)
    screen.text(textentry.heading)
    screen.move(10, 32)
    screen.text(textentry.txt)
    screen.move_rel(screen.get_text_size(textentry.txt) + 1, 3)
    screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
    screen.text_center("_")
    if textentry.warn ~= nil then
      screen.move(250, 90)
      screen.text_right(textentry.warn)
    end
  elseif m.mode == mPSET then
    screen.color(130, 140, 140)
    screen.move(10, 10)
    screen.text("PARAMETERS: PSET")
    screen.move(10, 28)
    screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
    if m.ps_action ~= 1 then
      screen.color(130, 140, 140, 100)
    end
    screen.text("SAVE")
    screen.move(50, 28)
    screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
    if m.ps_action ~= 2 then
      screen.color(130, 140, 140, 100)
    end
    screen.text("LOAD")
    screen.move(90, 28)
    screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
    if m.ps_action ~= 3 then
      screen.color(130, 140, 140, 100)
    end
    screen.text("DELETE")

    for i = 1, 8 do
      local n = i + m.ps_pos
      local line = "-"
      if pset[n] then
        line = pset[n].name
      end
      if i == 1 then
        screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
      else
        screen.color(130, 140, 140)
      end
      screen.move(10, (10 * i) + 35)
      if n < 100 then
        local num = (n == m.ps_last) and "*" .. n or n
        screen.text(num)
        screen.move(30, (10 * i) + 35)
        screen.text(line)
      end
    end
  elseif m.mode == mPSETSAVE then
    screen.move(10, 10)
    screen.color(130, 140, 140)
    screen.text(textentry.heading)
    screen.move(10, 32)
    screen.text(textentry.txt)
    screen.move_rel(screen.get_text_size(textentry.txt) + 1, 3)
    screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
    screen.text_center("_")
    screen.color(3, 138, 255)
    screen.move(10, 100)
    screen.text("escape: cancel")
    screen.move(10, 110)
    screen.text("enter: commit")
  elseif m.mode == mPSETEDIT then
    screen.move(128, 54)
    screen.color(237, 185, 94)
    screen.text_center("ENTER: DELETE PSET '" .. pset[m.ps_pos + 1].name .. "'")
    screen.move(128, 64)
    screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
    screen.text_center("BACKSPACE / ESCAPE: CANCEL")
  end

  screen.refresh()
  _seamstress.screen_set(1)
end

m.menu_midi_event = function(data, dev)
  if data.type == "cc" then
    local ch = data.ch
    local cc = data.cc
    local v = data.val
    if m.midi_learn.state then
      m.midi_learn.state = false
      m.dev = dev
      m.ch = ch
      m.cc = cc
      local p = page[m.pos + 1]
      local id = params:get_id(p)
      pmap.assign(id, m.dev, m.ch, m.cc)
      m.redraw()
    else
      local r = pmap.rev[dev][ch][cc]
      for param_target = 1, #r do
        local d = r[param_target]
        local prm_id = d
        d = params:lookup_param(prm_id).midi_mapping
        local t = params:t(prm_id)
        if d.accum then
          v = (v > 64) and 1 or -1
          d.value = util.clamp(d.value + v, d.in_lo, d.in_hi)
          v = d.value
        end
        local s = util.clamp(v, d.in_lo, d.in_hi)
        s = util.linlin(d.in_lo, d.in_hi, d.out_lo, d.out_hi, s)
        if t == params.tCONTROL or t == params.tTAPER then
          params:set_raw(prm_id, s)
        elseif t == params.tNUMBER or t == params.tOPTION then
          s = util.round(s)
          params:set(prm_id, s)
        elseif t == params.tBINARY then
          params:delta(prm_id, s)
          for i, param in ipairs(params.params) do
            if params:lookup_param(i).behavior == params:lookup_param(prm_id).behavior then
              if params:lookup_param(i).behavior == "trigger" then
                m.triggered[i] = 2
              else
                m.on[i] = params:get(i)
              end
            end
          end
        end
      end
      m.redraw()
    end
  end
end

m.init = function()
  if page == nil then
    build_page()
  end
  m.alt = false
  m.fine = false
  m.coarse = false
  m.redraw()
end

m.deinit = function() end

m.rebuild_params = function()
  if m.mode == mEDIT then
    if m.group then
      build_sub(m.groupid)
    else
      build_page()
    end
    m.redraw()
  end
end

m.mouse = function(x, y) end

m.click = function(x, y, state, button) end

return m

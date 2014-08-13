local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Screen = require("ui/screen")
local Menu = require("ui/widget/menu")

local Search = InputContainer:new{
    calibrefile = nil,
    search_dialog = nil,
    authors = 1,
    title = 2,
    path = 3,
    tags = 4,
    series = 5,
    authors2 = 6,
    series_index = 7,
    tags2 = 8,
    count = 0,
    data = {},
    results = {},
}

local function unichar (value)
-- this function is taken from dkjson
-- http://dkolf.de/src/dkjson-lua.fsl/
    local floor = math.floor
    local strchar = string.char
    if value < 0 then
        return nil
    elseif value <= 0x007f then
        return string.char (value)
    elseif value <= 0x07ff then
        return string.char (0xc0 + floor(value/0x40),0x80 + (floor(value) % 0x40))
    elseif value <= 0xffff then
        return string.char (0xe0 + floor(value/0x1000), 0x80 + (floor(value/0x40) % 0x40), 0x80 + (floor(value) % 0x40))
    elseif value <= 0x10ffff then
        return string.char (0xf0 + floor(value/0x40000), 0x80 + (floor(value/0x1000) % 0x40), 0x80 + (floor(value/0x40) % 0x40), 0x80 + (floor(value) % 0x40))
    else
        return nil
    end
end


local function findcalibre(root)
    local t = nil
    for entity in lfs.dir(root) do
        if t then
            break
        else
                if entity ~= "." and entity ~= ".." then
                      local fullPath=root .. "/" .. entity
                local mode = lfs.attributes(fullPath,"mode")
                if mode == "file" then
                    if entity == "metadata.calibre" or entity == ".metadata.calibre" then
                        t = root .. "/" .. entity
                    end
                elseif mode == "directory" then
                    t = findcalibre(fullPath)
                end
            end
        end
    end
    return t
end

function Search:init()
    local error = nil
    self.data = {}
    self.results = {}

    -- check if we find the calibre file
    if LIBRARY_PATH == nil then 
          self.calibrefile = findcalibre("/mnt")
          if not self.calibrefile then
              error = "LIBRARY_PATH in DEFAULTS.LUA is not set!"
          else
              UIManager:show(InfoMessage:new{text = _("Found calibre metadata at ") .. self.calibrefile .. _(". Save the default settings!")})
          end
    else
        if string.sub(LIBRARY_PATH,string.len(LIBRARY_PATH)) ~= "/" then
            LIBRARY_PATH = LIBRARY_PATH .. "/"
        end
        if io.open(LIBRARY_PATH .. "metadata.calibre","r") == nil then
            if io.open(LIBRARY_PATH .. ".metadata.calibre","r") == nil then
                   error = LIBRARY_PATH .. "metadata.calibre not found!"
            else
                self.calibrefile = LIBRARY_PATH .. ".metadata.calibre"
            end
        else
            self.calibrefile = LIBRARY_PATH .. "metadata.calibre"
        end

        if not (SEARCH_AUTHORS or SEARCH_TITLE or SEARCH_PATH or SEARCH_SERIES or SEARCH_TAGS) then
            self.calibrefile = nil
            UIManager:show(InfoMessage:new{text = _("You must specify at least one field to search at! (SEARCH_XXX = true in defaults.lua)")})
        elseif self.calibrefile == nil then
            self.calibrefile = findcalibre("/mnt")
        end
    end
    
    if self.calibrefile ~= nil then
        LIBRARY_PATH = string.gsub(self.calibrefile,"/[^/]*$","")
        if string.sub(LIBRARY_PATH,string.len(LIBRARY_PATH)) ~= "/" then
            LIBRARY_PATH = LIBRARY_PATH .. "/"
        end

        GLOBAL_INPUT_VALUE = self.search_value
        self.search_dialog = InputDialog:new{
            title = _("Search Books"),
            buttons = {
                {
                    {
                        text = _("Find"),
                        enabled = true,
                        callback = function()
                            self.search_value=self.search_dialog:getInputText()
                            self:close()
                        end,
                    },
                },
            },
            width = Screen:getWidth() * 0.8,
            height = Screen:getHeight() * 0.2,
        }
        GLOBAL_INPUT_VALUE = nil
        self.search_dialog:onShowKeyboard()
        UIManager:show(self.search_dialog)
    else
        if error then
            UIManager:show(InfoMessage:new{text = _(error .. " A search for a metadata.calibre file was not successful!"),})
        end
    end
end

function Search:close()
    self.search_dialog:onClose()
    UIManager:close(self.search_dialog)
    if string.len(self.search_value) > 0 then
        self:find()
    end
end

function Search:find()
    local f = io.open(self.calibrefile)
    local line = f:read()
    local i = 1
    local upsearch
    local dummy

    -- removes leading and closing characters and converts hex-unicodes
    local ReplaceHexChars = function(s,n,j)
        local l=string.len(s)

        if string.sub(s,l,l) == "\"" then
            s=string.sub(s,n,string.len(s)-1)
        else
            s=string.sub(s,n,string.len(s)-j)
        end

        s=string.gsub(s,"\\u([a-f0-9][a-f0-9][a-f0-9][a-f0-9])",function(w) return unichar(tonumber(w, 16)) end)

        return s
    end

    -- ready entries with multiple lines from calibre
    local ReadMultipleLines = function(s)
        self.data[i][s] = ""
        if s == self.authors then
            self.data[i][self.authors2] = ""
        elseif s == self.tags then
            self.data[i][self.tags2] = ""
        end
        while line ~= "    ], " do
            line = f:read()
            if line ~= "    ], " then
                self.data[i][s] = self.data[i][s] .. "," .. ReplaceHexChars(line,8,3)
                if s == self.authors then
                    self.data[i][self.authors2] = self.data[i][self.authors2] .. " & " .. ReplaceHexChars(line,8,3)
                elseif s == self.tags then
                    self.data[i][self.tags2] = self.data[i][self.tags2] .. " & " .. ReplaceHexChars(line,8,3)
                end
            end
        end
        self.data[i][s] = string.sub(self.data[i][s],2)
        if s == self.authors then
            self.data[i][self.authors2] = string.sub(self.data[i][self.authors2],4)
        elseif s == self.tags then
            self.data[i][self.tags2] = string.sub(self.data[i][self.tags2],4)
        end
    end

    if SEARCH_CASESENSITIVE then
        upsearch = self.search_value
    else
        upsearch = string.upper(self.search_value)
    end
    
    self.data[i] = {"-","-","-","-","-","-","-","-"}
    while line do
        if line == "  }, " or line == "  }" then
            -- new calibre data set

            dummy = ""
            if SEARCH_AUTHORS then dummy = dummy .. self.data[i][self.authors] end
            if SEARCH_TITLE then dummy = dummy .. self.data[i][self.title] end
            if SEARCH_PATH then dummy = dummy .. self.data[i][self.path] end
            if SEARCH_SERIES then dummy = dummy .. self.data[i][self.series] end
            if SEARCH_TAGS then dummy = dummy .. self.data[i][self.tags] end
            if not SEARCH_CASESENSITIVE then dummy = string.upper(dummy) end

            if string.find(dummy,upsearch,nil,true) then
                i = i + 1
            end
            self.data[i] = {"-","-","-","-","-","-","-","-"}

        elseif line == "    \"authors\": [" then -- AUTHORS
            ReadMultipleLines(self.authors)
        elseif line == "    \"tags\": [" then -- TAGS
            ReadMultipleLines(self.tags)
        elseif string.sub(line,1,11) == "    \"title\"" then -- TITLE
            self.data[i][self.title] = ReplaceHexChars(line,15,3)
        elseif string.sub(line,1,11) == "    \"lpath\"" then -- LPATH
            self.data[i][self.path] = ReplaceHexChars(line,15,3)
        elseif string.sub(line,1,12) == "    \"series\"" and line ~= "    \"series\": null, " then -- SERIES
            self.data[i][self.series] = ReplaceHexChars(line,16,3)
        elseif string.sub(line,1,18) == "    \"series_index\"" and line ~= "    \"series_index\": null, " then -- SERIES_INDEX
            self.data[i][self.series_index] = ReplaceHexChars(line,21,2)
        end
        line = f:read()
    end

    if f ~= nil then f:close() end

    i = i - 1
    if i > 0 then
        self.count = i
        self:showresults()
    else
        UIManager:show(InfoMessage:new{text = _("No match for " .. self.search_value)})
    end
end

function Search:onMenuHold(item)
    item.info = item.info .. item.path
    local f = io.open(item.path)
    if f == nil then
        item.info = item.info .. "\nFile not found!"
    else
        item.info = item.info .. "\n" .. string.format("%4.1fM",lfs.attributes(item.path, "size")/1024/1024)
        f:close()
    end
    UIManager:show(InfoMessage:new{text = item.info})
end

function Search:showresults()
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-50,
        height = Screen:getHeight()-50,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    local i = 1
    while i <= self.count do
        local dummy = _("Title: ")  .. (self.data[i][self.title] or "-") .. "\n \n" ..
                      _("Author(s): ") .. (self.data[i][self.authors2] or "-") .. "\n \n" ..
                      _("Tags: ") .. (self.data[i][self.tags2] or "-") .. "\n \n" ..
                      _("Series: ") .. (self.data[i][self.series] or "-")
        if self.data[i][self.series] ~= "-" then
            dummy = dummy .. " (" .. tostring(self.data[i][self.series_index]):gsub(".0$","") .. ")"
        end
        dummy = dummy .. "\n \n" .. _("Path: ")
        local book = LIBRARY_PATH .. self.data[i][self.path]
        table.insert(self.results, {
           info = dummy,
           path = LIBRARY_PATH .. self.data[i][self.path],
           text = self.data[i][self.authors] .. ": " .. self.data[i][self.title],
           callback = function()
              if book then
                  showReaderUI(book)
              end
           end
        })
        i = i + 1
    end
    self.search_menu:swithItemTable("Search Results", self.results)
    UIManager:show(menu_container)
end

return Search

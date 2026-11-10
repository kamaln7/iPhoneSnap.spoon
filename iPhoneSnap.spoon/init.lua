--- === iPhoneSnap ===
---
--- Take a photo with your iPhone through Continuity Camera, the "Take Photo"
--- Finder offers under Import from iPhone, and copy, save, edit or delete it
--- from a preview window.
---
--- The work happens in the bundled iphone-snap.swift, compiled with swiftc the
--- first time it is needed and again whenever it changes.
---
--- Download: https://github.com/kamaln7/iPhoneSnap.spoon

local obj = {}
obj.__index = obj

obj.name = "iPhoneSnap"
obj.version = "1.0"
obj.author = "Kamal Nasser"
obj.homepage = "https://github.com/kamaln7/iPhoneSnap.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- iPhoneSnap.saveDir
--- Variable
--- Folder Save and Save & Copy write the photo into. Default `~/Downloads`.
obj.saveDir = "~/Downloads"

--- iPhoneSnap.defaultAction
--- Variable
--- Action Return runs in the preview: "delete", "edit", "copy", "save" or
--- "saveCopy". Default "save".
obj.defaultAction = "save"

--- iPhoneSnap.edit
--- Variable
--- Function run by Edit with the path of a JPEG in the temporary folder.
--- Default: open it in the default app for JPEGs.
obj.edit = function(path)
  hs.open(path)
end

local source, binary, stamp

--- iPhoneSnap:init()
--- Method
--- Locates the bundled helper. Called by hs.loadSpoon(); binds nothing.
---
--- Returns:
---  * The iPhoneSnap object
function obj:init()
  source = hs.spoons.resourcePath("iphone-snap.swift")
  binary = hs.spoons.resourcePath("iphone-snap")
  -- Hash of the source the binary was built from. Archives keep old
  -- modification times, so comparing those would miss an updated Spoon.
  stamp = binary .. ".sha256"
  return self
end

local failures = {
  [2] = "No iPhone nearby for Continuity Camera",
}

local building
-- Every helper still running, kept referenced so it is not collected.
local captures = {}

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local data = file:read("a")
  file:close()
  return data
end

local function finished(self, code, stdout, stderr)
  -- 3: cancelled on either device or no photo; 15: replaced by a newer press.
  if code == 3 or code == 15 then
    return
  elseif code ~= 0 then
    hs.alert.show(failures[code] or ("iPhone photo failed: " .. stderr))
    return
  end
  local action, path = stdout:match("^(%a+)\t(.-)%s*$")
  if action == "save" then
    hs.alert.show("Saved " .. path:match("[^/]+$"))
  elseif action == "saveCopy" then
    hs.alert.show("Saved and copied " .. path:match("[^/]+$"))
  elseif action == "edit" then
    self.edit(path)
  elseif action == "copy" then
    hs.alert.show("Photo copied")
  end
end

local function startCapture(self)
  -- A helper still waiting for its photo exits; one showing a preview
  -- ignores this and stays open.
  for task in pairs(captures) do
    task:terminate()
  end
  local task
  task = hs.task.new(binary, function(code, stdout, stderr)
    captures[task] = nil
    finished(self, code, stdout, stderr)
  end, { "--save-dir", self.saveDir, "--default", self.defaultAction })
  captures[task] = true
  task:start()
end

--- iPhoneSnap:take()
--- Method
--- Opens the macOS "Take a photo" prompt on the iPhone, then the preview.
---
--- Returns:
---  * The iPhoneSnap object
function obj:take()
  if building and building:isRunning() then
    return self
  end
  local hash = hs.hash.SHA256(readFile(source))
  if hs.fs.attributes(binary) and readFile(stamp) == hash then
    startCapture(self)
    return self
  end
  building = hs.task.new("/usr/bin/xcrun", function(code, _, stderr)
    if code ~= 0 then
      hs.alert.show("iPhoneSnap build failed, see console")
      print(stderr)
      return
    end
    local file = io.open(stamp, "w")
    file:write(hash)
    file:close()
    startCapture(self)
  end, { "swiftc", "-O", source, "-o", binary })
  building:start()
  return self
end

--- iPhoneSnap:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for iPhoneSnap
---
--- Parameters:
---  * mapping - A table with the key `take` set to a hotkey spec, e.g.
---    `{ take = {{"shift"}, "f13"} }`
---
--- Returns:
---  * The iPhoneSnap object
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({ take = hs.fnutils.partial(self.take, self) }, mapping)
  return self
end

return obj

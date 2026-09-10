-- Stub of just enough ESO client to exercise PB's MailerExtension.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload,
-- boot the machine, log in, open mail. What is stubbed here is only what the add-on actually
-- touches -- the queued-attachment calls, a backpack whose contents can be moved around
-- underneath a draft, both mail interfaces, and saved variables -- so the part that decides
-- what a draft is and where an item went can be exercised here instead.
--
-- The two mail interfaces are stubbed as the two different shapes they really are: the
-- keyboard one as edit controls hanging off MAIL_SEND, the gamepad one as a view control
-- driven through the ZO_MailView_*_Gamepad functions. A draft saved in one and restored in
-- the other is a test, not an assumption.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value)
	if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end
	stringValues[_G[id]] = value
end
function SafeAddVersion() end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- The client's own mail strings, which Compose.lua borrows rather than writing its own.
ZO_CreateStringId("SI_MAIL_ALREADY_ATTACHED", "That item is already attached.")
ZO_CreateStringId("SI_MAIL_BOUND", "Bound items cannot be mailed.")
ZO_CreateStringId("SI_MAIL_ITEM_NOT_FOUND", "Item not found.")
ZO_CreateStringId("SI_MAIL_LOCKED", "That item is locked.")
ZO_CreateStringId("SI_STOLEN_ITEM_CANNOT_MAIL_MESSAGE", "Stolen items cannot be mailed.")
ZO_CreateStringId("SI_MAIL_ATTACHMENTS_FULL", "No free attachment slots.")

-- ---- chat / misc --------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) Chat[#Chat + 1] = t end }
function ChatClear() Chat = {} end
function ChatLast() return Chat[#Chat] end
function ChatText() return table.concat(Chat, "\n") end
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}

function ZO_CommaDelimitNumber(n) return tostring(n) end

-- ---- alerts and dialogs -------------------------------------------------------------
--
-- The alert is the only answer somebody playing on a controller with the chat window closed
-- ever sees, so it is recorded and checked like any other output.
UI_ALERT_CATEGORY_ALERT = "ALERT"
UI_ALERT_CATEGORY_ERROR = "ERROR"
SOUNDS = { NONE = "NONE", NEGATIVE_CLICK = "NEGATIVE_CLICK" }
GAMEPAD_DIALOGS = { BASIC = "BASIC" }
ESO_Dialogs = {}

Alerts = {}
function ZO_Alert(category, sound, text) Alerts[#Alerts + 1] = tostring(text) end
function AlertsClear() Alerts = {} end
function AlertText() return table.concat(Alerts, "\n") end

-- Whether the confirm dialog is answered yes or no. The default is no, so a test that means
-- to delete something has to say so.
DialogAnswer = false
LastDialog = nil

function ZO_Dialogs_ShowPlatformDialog(name, data, textParams)
	LastDialog = { name = name, data = data, textParams = textParams }
	if DialogAnswer then
		local dialog = { data = data }
		ESO_Dialogs[name].buttons[1].callback(dialog)
	end
end

GamepadPreferred = false
function IsInGamepadPreferredMode() return GamepadPreferred end

function GetTimeStamp() return 1757400000 end

-- The frame clock, moved by hand. The auto-save asks it how long it has been, so a test that
-- wants the next save to happen says so rather than waiting for it.
FrameMilliseconds = 0
function GetFrameTimeMilliseconds() return FrameMilliseconds end
function AdvanceSeconds(seconds) FrameMilliseconds = FrameMilliseconds + seconds * 1000 end
function GetDate() return 20260909 end
function GetTimeString() return "12:34:56" end

function ManifestLine(field)
	local file = io.open(DIR .. "/PBsMailerExtension.addon", "r")
	if not file then return nil end
	local found
	for line in file:lines() do
		found = found or line:match("^## " .. field .. ":%s*(.-)%s*$")
	end
	file:close()
	return found
end

-- The add-on manager, including the disk figures. They are methods on the manager rather than
-- global functions, which is the thing worth getting right here.
StorageCapacityMB = 5
StorageUsedMB = 1.25
StorageMineMB = 0.25
StorageAnswers = true

function GetAddOnManager()
	if not StorageAnswers then
		return {
			GetNumAddOns = function() return 1 end,
			GetAddOnInfo = function(_, i) return "PBsMailerExtension", ManifestLine("Title") end,
		}
	end

	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i)
			return "PBsMailerExtension", ManifestLine("Title")
		end,
		GetTotalUserAddOnSavedVariablesDiskCapacityMB = function() return StorageCapacityMB end,
		GetTotalUserAddOnSavedVariablesDiskUsageMB = function() return StorageUsedMB end,
		GetUserAddOnSavedVariablesDiskUsageMB = function(_, index) return StorageMineMB end,
	}
end

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
EVENT_MAIL_SEND_SUCCESS = "EVENT_MAIL_SEND_SUCCESS"

local handlers = {}
local updates = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, namespace, event, fn)
		handlers[event] = handlers[event] or {}
		handlers[event][namespace] = fn
	end,
	UnregisterForEvent = function(_, namespace, event)
		if handlers[event] then handlers[event][namespace] = nil end
	end,

	-- The client's update timer, driven by hand: Tick() is one turn of it. The sent box
	-- keeps its copy of the Send page this way, so the tests decide exactly when a copy is
	-- taken and can put a send in between two of them.
	RegisterForUpdate = function(_, name, ms, fn) updates[name] = fn end,
	UnregisterForUpdate = function(_, name) updates[name] = nil end,
}

function Tick()
	for _, fn in pairs(updates) do fn() end
end

function Watching()
	local n = 0
	for _ in pairs(updates) do n = n + 1 end
	return n
end

function Fire(event, ...)
	for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end
end

-- ---- saved variables ----------------------------------------------------------------
local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = DeepCopy(v) end
	return copy
end

ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		return DeepCopy(defaults or {})
	end,
}

-- ---- the backpack -------------------------------------------------------------------
--
-- Slots are 0-based, as they are in the client. A slot is nil, or a table of
-- { instance, link, name, stack }. The tests move these around underneath a saved draft,
-- which is the whole point of the harness.
BAG_BACKPACK = 1
LINK_STYLE_DEFAULT = 0

Backpack = {}

function BackpackReset()
	Backpack = {}
	LinkNames = {}
end

function BackpackPut(slotIndex, instance, link, name, stack)
	Backpack[slotIndex] = { instance = instance, link = link, name = name, stack = stack or 1 }
	LinkNames[link] = name
end

function BackpackClear(slotIndex)
	Backpack[slotIndex] = nil
end

function BackpackMove(from, to)
	Backpack[to] = Backpack[from]
	Backpack[from] = nil
end

function GetBagSize(bagId) return 16 end

local function Slot(bagId, slotIndex)
	if bagId ~= BAG_BACKPACK then return nil end
	return Backpack[slotIndex]
end

function GetItemInstanceId(bagId, slotIndex)
	local slot = Slot(bagId, slotIndex)
	return slot and slot.instance or nil
end

function GetItemLink(bagId, slotIndex, style)
	local slot = Slot(bagId, slotIndex)
	return slot and slot.link or ""
end

-- The client answers "what is this link called" from its own item database, so the harness
-- keeps one: whatever name a link was put into the backpack under.
LinkNames = {}

function GetItemLinkName(link) return LinkNames[link] or "" end

ZO_CreateStringId("SI_TOOLTIP_ITEM_NAME", "<<t:1>>")

function zo_strformat(formatId, argument)
	if formatId == SI_TOOLTIP_ITEM_NAME then
		return LinkNames[argument] or argument
	end
	return tostring(argument)
end

function GetItemName(bagId, slotIndex)
	local slot = Slot(bagId, slotIndex)
	return slot and slot.name or ""
end

function GetSlotStackSize(bagId, slotIndex)
	local slot = Slot(bagId, slotIndex)
	return slot and slot.stack or 0
end

-- ---- the queued mail ----------------------------------------------------------------
MAIL_MAX_ATTACHED_ITEMS = 6

MAIL_ATTACHMENT_RESULT_SUCCESS = 0
MAIL_ATTACHMENT_RESULT_ALREADY_ATTACHED = 1
MAIL_ATTACHMENT_RESULT_BOUND = 2
MAIL_ATTACHMENT_RESULT_ITEM_NOT_FOUND = 3
MAIL_ATTACHMENT_RESULT_LOCKED = 4
MAIL_ATTACHMENT_RESULT_PLAYER_LOCKED = 5
MAIL_ATTACHMENT_RESULT_STOLEN = 6

local queued = {}
local queuedGold = 0
local queuedCod = 0

-- Set by a test to make the next attach refuse, the way a bound or stolen item would.
AttachRefusal = nil

function QueueReset()
	queued = {}
	queuedGold = 0
	queuedCod = 0
	AttachRefusal = nil
end

function GetQueuedItemAttachmentInfo(slot)
	local entry = queued[slot]
	if not entry then return 0, 0, "", 0 end
	return entry.bagId, entry.slotIndex, "icon", GetSlotStackSize(entry.bagId, entry.slotIndex)
end

function CanQueueItemAttachment(bagId, slotIndex, attachSlot)
	return Slot(bagId, slotIndex) ~= nil
end

function QueueItemAttachment(bagId, slotIndex, attachSlot)
	if AttachRefusal then
		local refusal = AttachRefusal
		AttachRefusal = nil
		return refusal
	end
	if not Slot(bagId, slotIndex) then
		return MAIL_ATTACHMENT_RESULT_ITEM_NOT_FOUND
	end
	queued[attachSlot] = { bagId = bagId, slotIndex = slotIndex }
	return MAIL_ATTACHMENT_RESULT_SUCCESS
end

function RemoveQueuedItemAttachment(slot)
	queued[slot] = nil
end

function QueueMoneyAttachment(amount) queuedGold = amount or 0 end
function GetQueuedMoneyAttachment() return queuedGold end
function QueueCOD(amount) queuedCod = amount or 0 end
function GetQueuedCOD() return queuedCod end

function QueuedSlots()
	local n = 0
	for slot = 1, MAIL_MAX_ATTACHED_ITEMS do
		if queued[slot] then n = n + 1 end
	end
	return n
end

function QueuedNameAt(slot)
	local entry = queued[slot]
	if not entry then return nil end
	return GetItemName(entry.bagId, entry.slotIndex)
end

-- ---- the inbox ----------------------------------------------------------------------
--
-- Enough of a received mail to be copied: the header GetMailItemInfo answers with, a body the
-- client will only hand over once it has fetched it, and a list of attachments. The tests move
-- the selection around and take the body away, because "the client has not finished fetching
-- that mail" is a state a console really does spend time in.

Inbox = {}
OpenMailId = nil

function zo_getSafeId64Key(id) return "key" .. tostring(id) end

function InboxReset()
	Inbox = {}
	OpenMailId = nil
end

function InboxPut(mailId, mail)
	mail.attachments = mail.attachments or {}
	mail.ready = mail.ready ~= false
	Inbox[mailId] = mail
end

function OpenMail(mailId)
	OpenMailId = mailId
	MAIL_INBOX.isMailFromGuild = Inbox[mailId] and Inbox[mailId].fromGuild or false
end

function GetMailItemInfo(mailId)
	local mail = Inbox[mailId]
	if not mail then return "", "", "" end
	return mail.sender or "", mail.senderCharacter or "", mail.subject or "", "icon",
		false, mail.fromSystem or false, false, false,
		#mail.attachments, mail.gold or 0, mail.cod or 0, mail.expiresInDays or 30, 0, 1
end

function ReadMail(mailId)
	local mail = Inbox[mailId]
	return mail and mail.body or ""
end

function IsReadMailInfoReady(mailId)
	local mail = Inbox[mailId]
	return mail and mail.ready or false
end

function GetAttachedItemLink(mailId, index, style)
	local mail = Inbox[mailId]
	local item = mail and mail.attachments[index]
	return item and item.link or ""
end

function GetAttachedItemInfo(mailId, index)
	local mail = Inbox[mailId]
	local item = mail and mail.attachments[index]
	return "icon", item and item.stack or 0
end

function GetGuildMailItemInfo(mailId)
	local mail = Inbox[mailId]
	if not mail then return 0, "", "" end
	return mail.guildId or 1, mail.subject or "", mail.body or "",
		mail.expiresInDays or 30, 0, 0, mail.sender or ""
end

function IsValidGuildMail(mailId)
	local mail = Inbox[mailId]
	return mail ~= nil and mail.fromGuild == true
end

function GetGuildName(guildId) return "The Guild " .. tostring(guildId) end

MAIL_INBOX = {}
function MAIL_INBOX:GetOpenMailId() return OpenMailId end

-- ---- an edit control ----------------------------------------------------------------
local function EditControl()
	local control = { text = "" }
	function control:GetText() return self.text end
	function control:SetText(value) self.text = value or "" end
	return control
end

-- ---- the keyboard interface ---------------------------------------------------------
MAIL_SEND = {
	to = EditControl(),
	subject = EditControl(),
	body = EditControl(),
	hidden = true,
}
function MAIL_SEND:IsHidden() return self.hidden end

-- ---- the gamepad interface ----------------------------------------------------------
SCENE_FRAGMENT_SHOWN = "SHOWN"
SCENE_FRAGMENT_HIDDEN = "HIDDEN"

local gamepadView = {
	addressEdit = { edit = EditControl() },
	subjectEdit = { edit = EditControl() },
	bodyEdit = { edit = EditControl() },
}

function ZO_MailView_GetAddress_Gamepad(control) return control.addressEdit.edit:GetText() end
function ZO_MailView_GetSubject_Gamepad(control) return control.subjectEdit.edit:GetText() end
function ZO_MailView_GetBody_Gamepad(control) return control.bodyEdit.edit:GetText() end

function ZO_MailView_Display_Gamepad(control, codFee, attachedMoney, address, subject, body)
	if address then control.addressEdit.edit:SetText(address) end
	if subject then control.subjectEdit.edit:SetText(subject) end
	if body then control.bodyEdit.edit:SetText(body) end
end

local gamepadSend = { mailView = gamepadView }
local gamepadInbox = {}
function gamepadInbox:GetActiveMailId() return OpenMailId end
function gamepadInbox:IsActiveMailFromGuild() return Inbox[OpenMailId] and Inbox[OpenMailId].fromGuild or false end

MAIL_GAMEPAD = { send = gamepadSend, inbox = gamepadInbox }
function MAIL_GAMEPAD:GetSend() return self.send end
function MAIL_GAMEPAD:GetInbox() return self.inbox end

GAMEPAD_MAIL_SEND_FRAGMENT = { state = SCENE_FRAGMENT_HIDDEN }
function GAMEPAD_MAIL_SEND_FRAGMENT:GetState() return self.state end

-- ---- which page is open -------------------------------------------------------------
--
-- One switch for the tests, because "no page open" is a state the add-on has to survive and
-- is the easiest one to forget to check.
function OpenKeyboard()
	MAIL_SEND.hidden = false
	GAMEPAD_MAIL_SEND_FRAGMENT.state = SCENE_FRAGMENT_HIDDEN
end

function OpenGamepad()
	MAIL_SEND.hidden = true
	GAMEPAD_MAIL_SEND_FRAGMENT.state = SCENE_FRAGMENT_SHOWN
end

function CloseMail()
	MAIL_SEND.hidden = true
	GAMEPAD_MAIL_SEND_FRAGMENT.state = SCENE_FRAGMENT_HIDDEN
end

function PageText()
	if not MAIL_SEND.hidden then
		return MAIL_SEND.to:GetText(), MAIL_SEND.subject:GetText(), MAIL_SEND.body:GetText()
	end
	return gamepadView.addressEdit.edit:GetText(),
		gamepadView.subjectEdit.edit:GetText(),
		gamepadView.bodyEdit.edit:GetText()
end

function KeyboardPageText()
	return MAIL_SEND.to:GetText(), MAIL_SEND.subject:GetText(), MAIL_SEND.body:GetText()
end

function GamepadPageText()
	return gamepadView.addressEdit.edit:GetText(),
		gamepadView.subjectEdit.edit:GetText(),
		gamepadView.bodyEdit.edit:GetText()
end

function SetPageText(to, subject, body)
	if not MAIL_SEND.hidden then
		MAIL_SEND.to:SetText(to)
		MAIL_SEND.subject:SetText(subject)
		MAIL_SEND.body:SetText(body)
	else
		ZO_MailView_Display_Gamepad(gamepadView, nil, nil, to, subject, body)
	end
end

-- ---- load the add-on ----------------------------------------------------------------
function LoadAddOn()
	PBS_MAILER_EXTENSION = nil
	updates = {}
	FrameMilliseconds = 0
	dofile(DIR .. "/lang/strings.lua")
	dofile(DIR .. "/Main.lua")
	dofile(DIR .. "/Compose.lua")
	dofile(DIR .. "/Box.lua")
	dofile(DIR .. "/Drafts.lua")
	dofile(DIR .. "/Sent.lua")
	dofile(DIR .. "/Keep.lua")
	dofile(DIR .. "/UI.lua")
	-- The two interface files are loaded as well. Nothing in this harness can drive the screens
	-- they hook into, and their Initialize is never called -- but loading them proves their main
	-- chunks are what a main chunk should be: a guard, some locals and a pile of function
	-- definitions. A stray line of executable code at the top of one of these is the kind of
	-- mistake that costs a console session, and it is free to catch here.
	dofile(DIR .. "/Gamepad.lua")
	dofile(DIR .. "/Keyboard.lua")
	Fire(EVENT_ADD_ON_LOADED, "PBsMailerExtension")
	-- Activation is fired too, because that is when the two interfaces are wired up. Neither
	-- Gamepad.lua nor Keyboard.lua is loaded here -- they are hooks into screens this harness
	-- does not have -- so what this checks is that their absence is survivable, which is the
	-- same path a client takes when a hook target is missing.
	Fire(EVENT_PLAYER_ACTIVATED)
	return PBS_MAILER_EXTENSION
end

function Command(text)
	ChatClear()
	AlertsClear()
	SLASH_COMMANDS["/pbmail"](text)
	return ChatText()
end

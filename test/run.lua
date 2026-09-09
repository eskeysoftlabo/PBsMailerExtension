-- Behavioural tests for PB's MailerExtension.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)
--
-- What is worth testing here is what a draft is and what happens to it when the world has
-- moved on: an item that changed slot, an item that was replaced by another of the same kind,
-- an item that is simply gone, a page that is not open, a draft saved in one interface and
-- restored in the other. All of that is decided in Lua from values the client hands over, so
-- all of it can be checked on a laptop -- and every one of these checks is a console session
-- not spent finding out the same thing.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s", ok and "PASS" or "FAIL", label,
		tostring(got), tostring(want)))
end

local function checkContains(label, haystack, needle)
	local ok = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s in=%s", ok and "PASS" or "FAIL", label,
		tostring(haystack):gsub("\n", " | ")))
end

local function checkMissing(label, haystack, needle)
	local ok = type(haystack) == "string" and haystack:find(needle, 1, true) == nil
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s in=%s", ok and "PASS" or "FAIL", label,
		tostring(haystack):gsub("\n", " | ")))
end

local addon

-- A page with something on it: two items, some gold, and a letter.
local function GivenAPage()
	BackpackReset()
	QueueReset()
	BackpackPut(3, 1001, "|H1:item:30148|hjute|h", "Jute", 40)
	BackpackPut(7, 1002, "|H1:item:23265|hironingot|h", "Iron Ingot", 12)
	SetPageText("@Someone", "Materials", "Here is the jute you asked for.")
	QueueItemAttachment(BAG_BACKPACK, 3, 1)
	QueueItemAttachment(BAG_BACKPACK, 7, 2)
	QueueMoneyAttachment(500)
end

-- What the client's own Clear does to the page, so a restore is restoring into a blank page
-- rather than on top of itself.
local function ClearPage()
	SetPageText("", "", "")
	for slot = 1, MAIL_MAX_ATTACHED_ITEMS do
		RemoveQueuedItemAttachment(slot)
	end
	QueueMoneyAttachment(0)
	QueueCOD(0)
end

local function Reset()
	BackpackReset()
	QueueReset()
	InboxReset()
	-- Both pages, not just the one about to be used: an edit box left holding the last test's
	-- letter is state leaking from one test into the next, and the sent box takes a copy of
	-- the page the moment it opens.
	OpenKeyboard()
	ClearPage()
	OpenGamepad()
	ClearPage()
	CloseMail()
	addon = LoadAddOn()
end

-- ---- identity -----------------------------------------------------------------------

Reset()
check("version comes from the manifest", addon.version, ManifestLine("Version"))

checkContains("where reports the tabs it could not wire", Command("where"), "keyboard")

-- ---- nothing open -------------------------------------------------------------------

Reset()
checkContains("where, with no page open", Command("where"), "not open")
checkContains("save, with no page open", Command("save"), "not open")
checkContains("list, with nothing saved", Command("list"), "No drafts saved")

-- ---- refusing to save nothing -------------------------------------------------------

Reset()
OpenKeyboard()
ClearPage()
checkContains("save, with a blank page", Command("save"), "empty")
check("a blank page saved nothing", #addon.drafts:All(), 0)

-- ---- saving -------------------------------------------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
local out = Command("save jute")
checkContains("save says which draft it made", out, "Saved as draft 1")
checkContains("the description carries the name", out, "jute")
checkContains("the description carries the addressee", out, "@Someone")
checkContains("the description counts the attachments", out, "2 items")
checkContains("the description carries the gold", out, "500g")
checkContains("the description carries the date", out, "2026-09-09 12:34")
check("one draft is stored", #addon.drafts:All(), 1)

local draft = addon.drafts:At(1)
check("the body was captured", draft.body, "Here is the jute you asked for.")
check("both attachments were captured", #draft.attachments, 2)
check("the attachment remembers its stack", draft.attachments[1].itemInstanceId, 1001)

-- ---- restoring, with nothing moved ---------------------------------------------------

ClearPage()
out = Command("load 1")
checkContains("load says it is on the page", out, "draft 1 is on the page")
local to, subject, body = PageText()
check("the addressee came back", to, "@Someone")
check("the subject came back", subject, "Materials")
check("the body came back", body, "Here is the jute you asked for.")
check("both attachments came back", QueuedSlots(), 2)
check("the first attachment is the right item", QueuedNameAt(1), "Jute")
check("the gold came back", GetQueuedMoneyAttachment(), 500)
check("loading did not consume the draft", #addon.drafts:All(), 1)

-- ---- restoring, with the backpack rearranged -----------------------------------------

ClearPage()
BackpackMove(3, 11)
out = Command("load 1")
check("an item that changed slot is still found", QueuedSlots(), 2)
check("and it is still the same item", QueuedNameAt(1), "Jute")
checkMissing("so nothing is reported", out, "not in your backpack")

-- ---- restoring, when the stack was replaced by another of the same kind ---------------

ClearPage()
BackpackClear(11)
BackpackPut(2, 9999, "|H1:item:30148|hjute|h", "Jute", 200)
out = Command("load 1")
check("a different stack of the same item is used", QueuedSlots(), 2)
check("and it is the right kind", QueuedNameAt(1), "Jute")

-- ---- restoring, when the item is gone -------------------------------------------------

ClearPage()
BackpackClear(2)
out = Command("load 1")
checkContains("an item that is gone is reported", out, "not in your backpack")
checkContains("and it is named", out, "Jute")
check("the rest of the mail still went back", QueuedSlots(), 1)
to, subject, body = PageText()
check("the text still went back", subject, "Materials")

-- ---- restoring, when the client refuses the attach -------------------------------------

ClearPage()
BackpackPut(2, 9999, "|H1:item:30148|hjute|h", "Jute", 200)
AttachRefusal = MAIL_ATTACHMENT_RESULT_BOUND
out = Command("load 1")
checkContains("a refused attach is reported in the client's words", out, "Bound items cannot be mailed")

-- ---- C.O.D. ---------------------------------------------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
QueueMoneyAttachment(0)
QueueCOD(750)
Command("save cod")
ClearPage()
out = Command("load 1")
checkContains("a C.O.D. is reported rather than set", out, "750")
check("and it was not put into the queue", GetQueuedCOD(), 0)

Reset()
OpenKeyboard()
GivenAPage()
Command("save gold")
ClearPage()
QueueCOD(300)
out = Command("load 1")
checkContains("gold is not set behind a C.O.D. page", out, "set to C.O.D.")
check("and the gold was left alone", GetQueuedMoneyAttachment(), 0)

-- ---- saved on one interface, restored on the other -------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
Command("save crossing")
ClearPage()
OpenGamepad()
ClearPage()
out = Command("load 1")
checkContains("a keyboard draft loads on the gamepad page", out, "on the page")
to, subject, body = PageText()
check("the gamepad addressee came back", to, "@Someone")
check("the gamepad subject came back", subject, "Materials")
check("the gamepad attachments came back", QueuedSlots(), 2)
checkContains("and the add-on knows which page it is on", Command("where"), "gamepad")

-- ---- listing, numbering and deleting ---------------------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
Command("save first")
SetPageText("@Other", "Second", "second body")
Command("save second")
SetPageText("@Third", "Third", "third body")
Command("save third")
check("three drafts", #addon.drafts:All(), 3)

out = Command("list")
checkContains("the list is numbered", out, "1. first")
checkContains("and saving appended rather than renumbered", out, "3. third")

out = Command("delete 2")
checkContains("delete says what it threw away", out, "second")
check("two drafts left", #addon.drafts:All(), 2)
check("the third moved up", addon.drafts:At(2).name, "third")

checkContains("delete all says how many", Command("delete all"), "2")
check("nothing left", #addon.drafts:All(), 0)

-- ---- refusals --------------------------------------------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
Command("save one")
checkContains("a number nobody has", Command("load 99"), "no draft 99")
checkContains("a word where a number goes", Command("load jute"), "Which draft")
checkContains("an unknown command says so", Command("nonsense"), "do not know")
checkContains("and then offers the help", Command("nonsense"), "/pbmail list")
checkContains("no arguments is the help", Command(""), "/pbmail save")

-- ---- what is said over the game ---------------------------------------------------------
--
-- The alert matters as much as the chat line: on a controller with the chat window closed it
-- is the whole of the answer.

Reset()
OpenKeyboard()
GivenAPage()
Command("save alerts")
checkContains("saving says so over the game", AlertText(), "1")
ClearPage()
Command("load 1")
checkContains("loading says so over the game", AlertText(), "on the page")

BackpackReset()
ClearPage()
Command("load 1")
checkContains("and says how many things did not come back", AlertText(), "2")

-- ---- loading while standing somewhere else ------------------------------------------------
--
-- The add-on must never bring the Send page up itself. Doing that runs the client's own
-- OnShowing -> PopulateMainList from our frame, and the closure that sends the mail is created
-- in there -- born untrusted, and the Send button then fails on a private function
-- (FINDINGS §9). So the letter is written onto the compose page from wherever the player is,
-- and they are told to walk over to it.

Reset()
OpenKeyboard()
GivenAPage()
Command("save deferred")
ClearPage()
CloseMail()

out = Command("load 1")
to, subject, body = KeyboardPageText()
check("the letter is written even with the page not showing", to, "@Someone")
check("all of it", subject, "Materials")
check("attachments and all", QueuedSlots(), 2)
checkContains("and the player is told where to find it", out, "Send tab")
checkContains("said over the game as well", AlertText(), "Send tab")

-- Nothing was asked of the client's screens: no tab was changed, no scene was shown.
check("no pending state is left behind", addon.ui.pending, nil)

-- With the page already showing there is nowhere to walk to, so it is not said.
ClearPage()
OpenKeyboard()
out = Command("load 1")
checkMissing("with the page in front of you, nothing to walk to", out, "Send tab")

-- The surface written to follows the interface being played in, so a controller player is
-- never handed a keyboard page.
Reset()
OpenKeyboard()
GivenAPage()
Command("save modes")
ClearPage()
CloseMail()

GamepadPreferred = true
Command("load 1")
to = GamepadPageText()
check("in gamepad mode the gamepad page is written", to, "@Someone")
to = KeyboardPageText()
check("and the keyboard page is left alone", to, "")

GamepadPreferred = false

-- ---- deleting from a button ---------------------------------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
Command("save one")
Command("save two")

DialogAnswer = false
addon.ui:ConfirmDelete(addon.drafts, 1)
check("a draft is not deleted until the dialog says so", #addon.drafts:All(), 2)
checkContains("and the dialog was the confirm dialog", LastDialog.name, "CONFIRM_DELETE_DRAFT")

DialogAnswer = true
local removed = 0
addon.ui:ConfirmDelete(addon.drafts, 1, function() removed = removed + 1 end)
check("and deleted when it does", #addon.drafts:All(), 1)
check("with the list told to redraw itself", removed, 1)
DialogAnswer = false

-- ---- the wall --------------------------------------------------------------------------

Reset()
OpenKeyboard()
GivenAPage()
for i = 1, addon.drafts:Max() do
	Command("save number " .. i)
end
check("saved up to the limit", #addon.drafts:All(), addon.drafts:Max())
checkContains("and refuses past it", Command("save one too many"), "limit")
check("without dropping anything", #addon.drafts:All(), addon.drafts:Max())

-- ---- the sent box --------------------------------------------------------------------
--
-- The whole of the sent box rests on one thing: the copy of the page has to be taken BEFORE
-- the letter goes, because the client blanks the page in its own handler for the very event
-- that says the letter went -- and its handler was registered when the UI loaded, long before
-- any add-on existed. So every test here sends the way the client does: page, copy, clear,
-- event.

local function Send(recipient)
	Tick()          -- the copy the add-on keeps while the page is open
	ClearPage()     -- what the client's own EVENT_MAIL_SEND_SUCCESS handler does first
	Fire(EVENT_MAIL_SEND_SUCCESS, recipient or "@Someone")
end

Reset()
OpenKeyboard()
addon.ui:PageOpened()
GivenAPage()
Send("@Recipient")

check("a sent letter is recorded", #addon.sent:All(), 1)
local record = addon.sent:At(1)
check("with the subject that was on the page", record.subject, "Materials")
check("and the body", record.body, "Here is the jute you asked for.")
check("and the attachments", #record.attachments, 2)
check("and the gold", record.gold, 500)
check("and the addressee the server accepted, not the one typed", record.to, "@Recipient")
check("the drafts box was not touched", #addon.drafts:All(), 0)

checkContains("and it lists", Command("sent"), "1. Materials -> @Recipient")

-- What was attached has left the backpack, so what is kept is a description of it and not a
-- way back to a bag slot -- which would otherwise grab whatever has since moved into it.
check("the slot it came from is not kept", record.attachments[1].bagId, nil)
check("nor the stack it was", record.attachments[1].itemInstanceId, nil)
check("but what it was, is", record.attachments[1].name, "Jute")

-- ---- putting a sent letter back on the page ---------------------------------------------

ClearPage()
BackpackReset()
BackpackPut(4, 7777, "|H1:item:30148|hjute|h", "Jute", 10)
out = Command("sent load 1")
to, subject, body = PageText()
check("a sent letter goes back on the page", subject, "Materials")
check("the addressee comes with it", to, "@Recipient")
check("another of the same item is attached", QueuedSlots(), 1)
checkContains("and the one there is none of is reported", out, "Iron Ingot")
check("loading it did not consume the record", #addon.sent:All(), 1)

-- ---- nothing to record --------------------------------------------------------------------

Reset()
OpenKeyboard()
addon.ui:PageOpened()
ClearPage()
Send()
check("a send with nothing seen on the page records nothing", #addon.sent:All(), 0)

-- ---- the copy stops when the page closes ---------------------------------------------------

Reset()
OpenKeyboard()
addon.ui:PageOpened()
check("the page being open is what starts the copy", Watching(), 1)
addon.ui:PageClosed()
check("and closing it stops it", Watching(), 0)

-- ---- the sent box rolls, the drafts box refuses ---------------------------------------------
--
-- Opposite behaviour on purpose: a draft is something somebody chose to keep, so filling the
-- box refuses rather than throwing the oldest away. A log that stops recording once it is full
-- has stopped being a log.

Reset()
OpenKeyboard()
addon.ui:PageOpened()
for i = 1, addon.sent:Max() + 5 do
	GivenAPage()
	SetPageText("@Someone", "Letter " .. i, "body " .. i)
	Send()
end
check("the sent box never grows past its limit", #addon.sent:All(), addon.sent:Max())
checkContains("the newest is kept", addon.sent:Describe(addon.sent:At(addon.sent:Max())), "Letter " .. (addon.sent:Max() + 5))
checkContains("and the oldest was dropped", addon.sent:Describe(addon.sent:At(1)), "Letter 6")

-- ---- deleting from the sent box ---------------------------------------------------------

checkContains("sent delete says what it removed", Command("sent delete 1"), "Letter 6")
check("and it is gone", #addon.sent:All(), addon.sent:Max() - 1)
checkContains("sent delete all names the box and the count", Command("sent delete all"), "Sent")
check("leaving nothing", #addon.sent:All(), 0)
checkContains("and the empty box says why it might be empty", Command("sent"), "keeps no copy")

-- ---- the counts are told when they move ------------------------------------------------------
--
-- A tab's name carries how many letters its box holds, and the tab bar only re-reads that when
-- it is drawn again. Everything that adds or removes one has to say so, or the number sits
-- there being wrong until the next time somebody opens the mail window.

Reset()
local counted = 0
addon.ui:OnCountChanged(function() counted = counted + 1 end)

OpenKeyboard()
GivenAPage()
Command("save counted")
check("saving a draft says the count moved", counted, 1)

DialogAnswer = true
addon.ui:ConfirmDelete(addon.drafts, 1)
check("deleting through the dialog says so too", counted, 2)
DialogAnswer = false

GivenAPage()
Command("save again")
counted = 0
Command("delete 1")
check("and so does a typed delete", counted, 1)

Command("save one")
Command("save two")
counted = 0
Command("delete all")
check("and emptying a box", counted, 1)

-- Sending records a letter, which moves the sent box's count.
Reset()
addon.ui:OnCountChanged(function() counted = counted + 1 end)
OpenKeyboard()
addon.ui:PageOpened()
GivenAPage()
counted = 0
Send()
check("a letter going out moves the sent count", counted > 0, true)

-- ---- saving the letter being written ---------------------------------------------------------
--
-- One draft, kept up to date, and never a second one. It is the same copy the sent box takes,
-- so it costs no extra reading of the page, and it goes when the letter goes.

Reset()
OpenKeyboard()
addon.ui:PageOpened()
GivenAPage()

Tick()
check("what is being written is saved", #addon.drafts:All(), 1)
local auto = addon.drafts:At(1)
check("marked as the automatic one", auto.auto, true)
check("and named so it can be told apart", auto.name, GetString(SI_PBSMX_AUTOSAVE_NAME))
check("with what was on the page", auto.subject, "Materials")

-- Before the interval is up, nothing happens at all.
SetPageText("@Someone", "Materials", "second thoughts")
Tick()
check("a save inside the interval is not taken", addon.drafts:At(1).body, "Here is the jute you asked for.")

AdvanceSeconds(addon:AutoSaveSeconds())
Tick()
check("and the next one updates the same draft", #addon.drafts:All(), 1)
check("in place", addon.drafts:At(1).body, "second thoughts")
check("keeping which draft it is", addon.drafts:At(1).id, auto.id)

-- Clearing the page is somebody saying they are done with it.
ClearPage()
Tick()
check("clearing the page takes the automatic draft with it", #addon.drafts:All(), 0)

-- Sending does too.
GivenAPage()
Tick()
check("written again", #addon.drafts:All(), 1)
Send()
check("and sending takes it away", #addon.drafts:All(), 0)
check("while the sent box keeps the record", #addon.sent:All(), 1)

-- Off means off.
Reset()
OpenKeyboard()
addon.ui:PageOpened()
Command("autosave off")
GivenAPage()
Tick()
check("turned off, nothing is saved", #addon.drafts:All(), 0)
checkContains("and it says so", Command("autosave"), "Not saving")

Command("autosave 30")
checkContains("turned back on it says how often", Command("autosave"), "30")
check("and the setting took", addon:AutoSaveSeconds(), 30)
checkContains("a number nobody could mean", Command("autosave lots"), "How often")

-- A draft somebody saved themselves is never written over by this.
Reset()
OpenKeyboard()
addon.ui:PageOpened()
GivenAPage()
Command("save by hand")
Tick()
check("the automatic draft is a second draft, not the first one", #addon.drafts:All(), 2)
check("and the hand-saved one is untouched", addon.drafts:At(1).name, "by hand")
check("only the other is automatic", addon.drafts:At(2).auto, true)

-- ---- a draft that was sent ---------------------------------------------------------------------

Reset()
OpenKeyboard()
Command("autosave off")
GivenAPage()
Command("save posting")
ClearPage()
addon.ui:PageOpened()

Command("load 1")
check("the page is holding that draft", addon.ui.pageSource, addon.drafts:At(1).id)

out = Command("list")
Send()
check("sending it takes the draft with it", #addon.drafts:All(), 0)
check("and the sent box has what went", #addon.sent:All(), 1)

-- Off, the draft stays.
Reset()
OpenKeyboard()
Command("autosave off")
Command("onsend off")
GivenAPage()
Command("save keeping")
ClearPage()
addon.ui:PageOpened()
Command("load 1")
Send()
check("turned off, the draft is kept", #addon.drafts:All(), 1)
checkContains("and it says which way it is set", Command("onsend"), "kept")

-- A letter written from scratch belongs to no draft, and a kept or sent letter put back on the
-- page is a record: sending a copy of it must not use anything up.
Reset()
OpenKeyboard()
Command("autosave off")
addon.ui:PageOpened()
GivenAPage()
Send()
check("a letter from scratch takes nothing with it", #addon.drafts:All(), 0)

GivenAPage()
Command("save untouched")
ClearPage()
Command("sent load 1")
Send()
check("and sending a copy of a sent letter leaves the drafts alone", #addon.drafts:All(), 1)

-- ---- the kept box --------------------------------------------------------------------------
--
-- Everything in the inbox expires and an add-on cannot change that, so what this box does is
-- take a copy of what a letter SAID. The checks that matter most here are the two things it
-- must NOT do: claim to have kept the attachments, and put somebody else's items onto your
-- compose page when you answer them.

local function GivenAMail()
	InboxPut(11, {
		sender = "@Someone",
		senderCharacter = "Some Character",
		subject = "About the jute",
		body = "Thanks for the jute. Here is some gold back.",
		gold = 250,
		attachments = { { link = "|H1:item:30148|hjute|h", stack = 40 } },
	})
	OpenMail(11)
end

Reset()
checkContains("keeping with no mail open refuses", Command("keep save"), "No mail is open")
check("and keeps nothing", #addon.kept:All(), 0)

GivenAMail()
out = Command("keep save")
checkContains("a mail is kept", out, "Kept as 1")
checkContains("named by its subject and sender, arrow pointing in", out, "About the jute <- @Someone")
checkContains("and it says what it did NOT keep", out, "ATTACHED")

local mail = addon.kept:At(1)
check("the body was copied", mail.body, "Thanks for the jute. Here is some gold back.")
check("the sender is who it came from", mail.from, "@Someone")
check("and it is addressed back to them, so it can be answered", mail.to, "@Someone")
check("it is marked as something that arrived", mail.received, true)
check("what was attached is noted", #mail.attachments, 1)
check("and what it was is noted", mail.attachments[1].stack, 40)
check("as is the gold that came with it", mail.gold, 250)

checkContains("keeping the same one twice refuses", Command("keep save"), "already kept")
check("and does not keep it twice", #addon.kept:All(), 1)

-- The body only arrives when the client has fetched it; a kept letter with no body would be
-- worse than a refusal to keep it.
InboxPut(12, { sender = "@Other", subject = "Later", body = "", ready = false })
OpenMail(12)
checkContains("a mail the client has not fetched is refused", Command("keep save"), "not finished fetching")
check("and not kept", #addon.kept:All(), 1)

-- A letter from the game has nobody to answer.
InboxPut(13, { sender = "Announcements", subject = "Maintenance", body = "The servers...", fromSystem = true })
OpenMail(13)
Command("keep save")
check("a system mail is kept", #addon.kept:All(), 2)
check("with no addressee, rather than one that cannot be written to", addon.kept:At(2).to, "")

Reset()
counted = 0
addon.ui:OnCountChanged(function() counted = counted + 1 end)
GivenAMail()
Command("keep save")
check("keeping a mail says the count moved", counted, 1)
addon.ui:OnCountChanged(nil)

-- ---- guild mail ------------------------------------------------------------------------------
--
-- A different system with a different id space: GetGuildMailItemInfo hands back the body with
-- the header, so there is nothing to wait for. It is shown as coming from the guild and
-- addressed back to whoever in it pressed send.

Reset()
InboxPut(21, {
	fromGuild = true,
	guildId = 7,
	sender = "@Officer",
	subject = "Trader week",
	body = "We keep the trader this week. Bids by Friday.",
})
OpenMail(21)
out = Command("keep save")
checkContains("a guild mail can be kept", out, "Kept as 1")
local guildMail = addon.kept:At(1)
check("with its body", guildMail.body, "We keep the trader this week. Bids by Friday.")
check("shown as coming from the guild", guildMail.from, "The Guild 7")
check("and addressed back to whoever sent it", guildMail.to, "@Officer")
check("marked as guild mail", guildMail.fromGuild, true)
checkContains("and the preview names the sender behind the guild", addon.kept:Preview(guildMail), "@Officer")

checkContains("keeping the same guild mail twice refuses", Command("keep save"), "already kept")

-- Guild ids and mail ids are separate spaces, so the same number in each is two letters.
InboxPut(21, { sender = "@Someone", subject = "Ordinary 21", body = "different letter" })
OpenMail(21)
Command("keep save")
check("an ordinary mail with the same number is a different letter", #addon.kept:All(), 2)

-- ---- answering a kept mail ------------------------------------------------------------------

Reset()
OpenKeyboard()
GivenAMail()
Command("keep save")
ClearPage()
BackpackPut(3, 1001, "|H1:item:30148|hjute|h", "Jute", 40)

out = Command("keep load 1")
to, subject, body = PageText()
check("answering puts the sender in the To field", to, "@Someone")
check("and the subject", subject, "About the jute")
check("and the words", body, "Thanks for the jute. Here is some gold back.")
check("but NOT your own copy of what they sent you", QueuedSlots(), 0)
check("and not their gold either", GetQueuedMoneyAttachment(), 0)
check("keeping it did not consume the record", #addon.kept:All(), 1)

checkContains("the whole letter can be read from the command", Command("keep read 1"), "Thanks for the jute")

-- ---- the kept box refuses rather than rolls --------------------------------------------------

Reset()
Command("max keep 2")
check("the kept limit is a setting like the others", addon.kept:Max(), 2)
for i = 1, 2 do
	InboxPut(100 + i, { sender = "@Someone", subject = "Mail " .. i, body = "body " .. i })
	OpenMail(100 + i)
	Command("keep save")
end
check("filled to its limit", #addon.kept:All(), 2)
InboxPut(199, { sender = "@Someone", subject = "One too many", body = "body" })
OpenMail(199)
checkContains("and past it refuses rather than dropping the oldest", Command("keep save"), "limit is 2")
check("nothing was thrown away", #addon.kept:All(), 2)
checkContains("the oldest is still the oldest", addon.kept:Describe(addon.kept:At(1)), "Mail 1")

checkContains("and it is listed with the others", Command("max"), "Kept")

-- ---- how much each box keeps -------------------------------------------------------------
--
-- Two limits, both settings, and they behave in opposite ways on purpose. What is checked here
-- is mostly what does NOT happen: lowering a limit must never delete anything, because the
-- panel reports a slider while it is being dragged and an overshoot would otherwise be letters
-- gone for good.

Reset()
check("drafts start at their default", addon.drafts:Max(), addon.DEFAULT_MAX_DRAFTS)
check("sent starts at its default", addon.sent:Max(), addon.DEFAULT_MAX_SENT)
checkContains("max on its own reports both", Command("max"), "50")
checkContains("and the sent one too", Command("max"), "100")

checkContains("a limit can be set", Command("max drafts 20"), "20")
check("and it took", addon.drafts:Max(), 20)

OpenKeyboard()
GivenAPage()
for i = 1, 20 do
	SetPageText("@Someone", "Draft " .. i, "body")
	Command("save d" .. i)
end
check("the new limit is what fills the box", #addon.drafts:All(), 20)
checkContains("and past it refuses, naming both numbers", Command("save one more"), "20")

-- Lowering a limit deletes nothing, in either box.
Command("max drafts 5")
check("lowering the drafts limit deletes nothing", #addon.drafts:All(), 20)
checkContains("but it says the box is over", Command("max drafts 5"), "over")
checkContains("and saving still refuses", Command("save nope"), "5")
check("still nothing deleted", #addon.drafts:All(), 20)

Reset()
OpenKeyboard()
addon.ui:PageOpened()
for i = 1, 10 do
	GivenAPage()
	SetPageText("@Someone", "Letter " .. i, "body")
	Send()
end
check("ten sent", #addon.sent:All(), 10)

Command("max sent 3")
check("lowering the sent limit deletes nothing straight away", #addon.sent:All(), 10)

GivenAPage()
SetPageText("@Someone", "Letter 11", "body")
Send()
check("the next letter trims it to the new limit", #addon.sent:All(), 3)
checkContains("and the newest is the one just sent", addon.sent:Describe(addon.sent:At(3)), "Letter 11")

-- ---- the ceiling and the floor -------------------------------------------------------------

Reset()
Command("max sent 99999")
check("a limit above the ceiling is the ceiling", addon.sent:Max(), addon.LIMIT_CEILING)
Command("max drafts 0")
check("and below the floor is the floor", addon.drafts:Max(), addon.LIMIT_FLOOR)
checkContains("a box nobody named", Command("max nonsense 10"), "Which box")
checkContains("a number that is not one", Command("max drafts lots"), "How many")
check("and neither changed anything", addon.drafts:Max(), addon.LIMIT_FLOOR)

-- ---- result ----------------------------------------------------------------------------

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " FAILED")
	os.exit(1)
end

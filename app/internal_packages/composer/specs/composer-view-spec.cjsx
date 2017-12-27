_ = require "underscore"
React = require "react"
ReactDOM = require 'react-dom'
ReactTestUtils = require('react-dom/test-utils')

{Actions,
 Utils,
 File,
 Contact,
 Message,
 Account,
 DraftStore,
 DatabaseStore,
 MailspringTestUtils,
 AccountStore,
 ContactStore,
 FocusedContentStore,
 ComponentRegistry} = require "mailspring-exports"

{InjectedComponent,
 AttachmentItem,
 ImageAttachmentItem,
 ParticipantsTextField} = require 'mailspring-component-kit'

DraftEditingSession = require('../../../src/flux/stores/draft-editing-session').default
ComposerEditor = require('../lib/composer-editor').default
Fields = require('../lib/fields').default

u1 = new Contact(name: "Christine Spang", email: "spang@nylas.com")
u2 = new Contact(name: "Michael Grinich", email: "mg@nylas.com")
u3 = new Contact(name: "Evan Morikawa",   email: "evan@nylas.com")
u4 = new Contact(name: "Zoë Leiper",      email: "zip@nylas.com")
u5 = new Contact(name: "Ben Gotow",       email: "ben@nylas.com")

f1 = new File(id: 'file_1_id', filename: 'a.png', contentType: 'image/png', size: 10, object: "file")
f2 = new File(id: 'file_2_id', filename: 'b.pdf', contentType: '', size: 999999, object: "file")

users = [u1, u2, u3, u4, u5]

ComposerView = require("../lib/composer-view").default

# This will setup the mocks necessary to make the composer element (once
# mounted) think it's attached to the given draft. This mocks out the
# proxy system used by the composer.
DRAFT_ID = "local-123"
DRAFT_HEADER_MSG_ID = "test-header@message-id"

useDraft = (draftAttributes={}) ->
  @draft = new Message(Object.assign({id: DRAFT_ID, draft: true, body: "", headerMessageId: DRAFT_HEADER_MSG_ID}, draftAttributes))
  @session = new DraftEditingSession(DRAFT_HEADER_MSG_ID, @draft)
  # spyOn().andCallFake wasn't working properly on ensureCorrectAccount for some reason
  @session.ensureCorrectAccount = => Promise.resolve(@session)
  DraftStore._draftSessions[DRAFT_HEADER_MSG_ID] = @session
  @session._draftPromise

useFullDraft = ->
  useDraft.call @,
    from: [AccountStore.accounts()[0].me()]
    to: [u2]
    cc: [u3, u4]
    bcc: [u5]
    files: [f1, f2]
    subject: "Test Message 1"
    body: "Hello <b>World</b><br/> This is a test"
    replyToHeaderMessageId: null

makeComposer = (props={}) ->
  @composer = MailspringTestUtils.renderIntoDocument(
    <ComposerView draft={@draft} session={@session} {...props} />
  )
  advanceClock()

describe "ComposerView", ->
  beforeEach ->
    ComposerEditor.containerRequired = false
    ComponentRegistry.register(ComposerEditor, role: "Composer:Editor")

    spyOn(Actions, 'queueTask')
    spyOn(Actions, 'queueTasks')
    spyOn(DraftStore, "isSendingDraft").andCallThrough()
    spyOn(DraftEditingSession.prototype, 'changeSetCommit').andCallFake (draft) =>
      @draft = draft
    spyOn(ContactStore, "searchContacts").andCallFake (email) =>
      return _.filter(users, (u) u.email.toLowerCase() is email.toLowerCase())
    spyOn(Contact.prototype, "isValid").andCallFake (contact) ->
      return @email.indexOf('@') > 0

  afterEach ->
    ComposerEditor.containerRequired = undefined
    ComponentRegistry.unregister(ComposerEditor)
    DraftStore._cleanupAllSessions()
    MailspringTestUtils.removeFromDocument(@composer)

  describe "when sending a new message", ->
    it 'makes a request with the message contents', ->
      sessionSetupComplete = false
      useDraft.call(@).then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        editableNode = ReactDOM.findDOMNode(@composer).querySelector('[contenteditable]')
        spyOn(@session.changes, "add")
        editableNode.innerHTML = "Hello <strong>world</strong>"
        @composer._els[Fields.Body]._onDOMMutated(["mutated"])
        expect(@session.changes.add).toHaveBeenCalled()
        expect(@session.changes.add.calls.length).toBe 1
        body = @session.changes.add.calls[0].args[0].body
        expect(body).toBe "Hello <strong>world</strong>"
      )

  describe "when sending a reply-to message", ->
    beforeEach ->
      sessionSetupComplete = false
      useDraft.call(@,
        from: [u1]
        to: [u2]
        subject: "Test Reply Message 1"
        body: ""
        replyToHeaderMessageId: "1")
      .then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

      runs( =>
        makeComposer.call(@)
        @editableNode = ReactDOM.findDOMNode(@composer).querySelector('[contenteditable]')
        spyOn(@session.changes, "add")
      )

    it 'begins with empty body', ->
      expect(@editableNode.innerHTML).toBe ""

  describe "when sending a forwarded message", ->
    beforeEach ->
      @fwdBody = """<br><br><blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex;">
      ---------- Forwarded message ---------
      <br><br>
      From: Evan Morikawa &lt;evan@evanmorikawa.com&gt;<br>Subject: Test Forward Message 1<br>Date: Sep 3 2015, at 12:14 pm<br>To: Evan Morikawa &lt;evan@nylas.com&gt;
      <br><br>

      <meta content="text/html; charset=us-ascii">This is a test!
      </blockquote>"""

      sessionSetupComplete = false
      useDraft.call(@,
        from: [u1]
        to: [u2]
        subject: "Fwd: Test Forward Message 1"
        body: @fwdBody)
      .then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

      runs( =>
        makeComposer.call(@)
        @editableNode = ReactDOM.findDOMNode(@composer).querySelector('[contenteditable]')
        spyOn(@session.changes, "add")
      )

    it 'begins with the forwarded message expanded', ->
      expect(@editableNode.innerHTML).toBe @fwdBody

    it 'saves the full new body, plus forwarded text', ->
      @editableNode.innerHTML = "Hello <strong>world</strong>#{@fwdBody}"
      @composer._els[Fields.Body]._onDOMMutated(["mutated"])
      expect(@session.changes.add).toHaveBeenCalled()
      expect(@session.changes.add.calls.length).toBe 1
      body = @session.changes.add.calls[0].args[0].body
      expect(body).toBe """Hello <strong>world</strong>#{@fwdBody}"""

  describe "When sending a message", ->
    beforeEach ->
      spyOn(AppEnv, "isMainWindow").andReturn true
      {remote} = require('electron')
      @dialog = remote.dialog
      spyOn(remote, "getCurrentWindow")
      spyOn(@dialog, "showMessageBox")
      spyOn(Actions, "sendDraft").andCallThrough()

    it "shows an error if there are no recipients", ->
      sessionSetupComplete = false
      useDraft.call(@, subject: "no recipients").then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        status = @composer._isValidDraft()
        expect(status).toBe false
        expect(@dialog.showMessageBox).toHaveBeenCalled()
        dialogArgs = @dialog.showMessageBox.mostRecentCall.args[1]
        expect(dialogArgs.detail).toEqual("You need to provide one or more recipients before sending the message.")
        expect(dialogArgs.buttons).toEqual ['Edit Message', 'Cancel']
      )

    it "shows an error if a recipient is invalid", ->
      sessionSetupComplete = false
      useDraft.call(@,
        subject: 'hello world!'
        to: [new Contact(email: 'lol', name: 'lol')])
      .then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        status = @composer._isValidDraft()
        expect(status).toBe false
        expect(@dialog.showMessageBox).toHaveBeenCalled()
        dialogArgs = @dialog.showMessageBox.mostRecentCall.args[1]
        expect(dialogArgs.detail).toEqual("lol is not a valid email address - please remove or edit it before sending.")
        expect(dialogArgs.buttons).toEqual ['Edit Message', 'Cancel']
      )

    describe "not addressed to recipient warning", ->
      warn = (contactname, body) ->
        sessionSetupComplete = false
        useDraft.call(@, subject: "Subject", to: [new Contact(name: contactname, email:"mark@foundry376.com")], body: body).then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
        runs( =>
          makeComposer.call(@)
          status = @composer._isValidDraft()
          expect(status).toBe false
          expect(@dialog.showMessageBox).toHaveBeenCalled()
          dialogArgs = @dialog.showMessageBox.mostRecentCall.args[1]
          expect(dialogArgs.buttons).toEqual ['Send Anyway', 'Cancel']
        )

      noWarn = (contactname, body, email = "mark@foundry376.com") ->
        sessionSetupComplete = false
        useDraft.call(@, subject: "Subject", to: [new Contact(name: contactname, email: email)], body: body).then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
        runs( =>
          makeComposer.call(@)
          status = @composer._isValidDraft()
          expect(status).toBe true
          expect(@dialog.showMessageBox).not.toHaveBeenCalled()
        )

      it "warns a", -> warn.call(@, "Mark Teller", "Hey Ben, how's it going?")
      it "warns b", -> warn.call(@, "Mark Teller", "Morning Ben—I've got a great opportunity for you.")
      it "warns c", -> warn.call(@, "Mark Teller", "Yo Ben—This is great.")
      it "warns d", -> warn.call(@, "Mark Teller", "Yo MG-This is great.")
      it "warns e", -> warn.call(@, "Mark Teller", "Good afternoon Ben\nThis is great.")
      it "warns f", -> warn.call(@, "Mark Teller", "Hey Professor Tellor, check this out.")

      it "doesn't warn a", -> noWarn.call(@, "", "Hey Mark, check this out.")
      it "doesn't warn b", -> noWarn.call(@, null, "Hey Mark, check this out.")
      it "doesn't warn c", -> noWarn.call(@, "Mark Teller", "Hey Professor Mark, check this out.")
      it "doesn't warn c", -> noWarn.call(@, "Mark Teller", "Hey Professor Teller, check this out.")
      it "doesn't warn d", -> noWarn.call(@, "Mark Teller", "Hey Prof. Mark, check this out.")
      it "doesn't warn d", -> noWarn.call(@, "Mark Teller", "Hey Dr. Teller, check this out.")
      it "doesn't warn e", -> noWarn.call(@, "Mark Teller", "Morning dude check this out.")
      it "doesn't warn f", -> noWarn.call(@, "Mark Teller", "Hey man check this out.")
      it "doesn't warn g", -> noWarn.call(@, "Mark Teller", "Mark! This is great.")
      it "doesn't warn h", -> noWarn.call(@, "Mark Teller", "Yo Teller. This is great.")
      it "doesn't warn i", -> noWarn.call(@, "Mark Teller", "Yo MT! This is great.")
      it "doesn't warn i", -> noWarn.call(@, "Mark Teller", "Yo M! This is great.")
      it "doesn't warn j", -> noWarn.call(@, "Mark Teller", "Good afternoon Teller\nDude this is great.")
      it "doesn't warn k", -> noWarn.call(@, "Mark Teller", "Hey Mark, just wanted to see how it's going.")
      it "doesn't warn l", -> noWarn.call(@, "Mark Teller", "Hola. Just wanted to see how it's going.")
      it "doesn't warn m", -> noWarn.call(@, "Mark Teller", "Sénor—have a great opportunity for you.")
      it "doesn't warn n", -> noWarn.call(@, "Mark Teller", "Hey—just wanted to see how it's going.")

      # doesn't warn about lowercase names likely to be relational phrases
      it "doesn't warn o", -> noWarn.call(@, "Mark Teller", "Hey dad, check this out.")
      it "doesn't warn p", -> noWarn.call(@, "Mark Teller", "Hey guys, check this out.")

      # doesn't warn about common names / relational phrases even when capitalized
      it "doesn't warn q", -> noWarn.call(@, "Mark Teller", "Hey Dad, check this out.")
      it "doesn't warn r", -> noWarn.call(@, "Mark Teller", "Hey Grandpa, check this out.")
      it "doesn't warn s", -> noWarn.call(@, "Mark Teller", "Hey Ladies, check this out.")

      # doesn't warn when sending to a generic email address likely to have many names
      it "doesn't warn t", -> noWarn.call(@, "Foundry Support", "Morning Ben—hello world.", "support@foundry376.com")

    describe "empty body warning", ->
      it "warns if the body of the email is still the pristine body", ->
        pristineBody = "<br><br>"
        sessionSetupComplete = false
        useDraft.call(@,
          to: [u1]
          subject: "Hello World"
          body: pristineBody)
        .then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

        runs( =>
          makeComposer.call(@)
          spyOn(@session, 'draftPristineBody').andCallFake -> pristineBody

          status = @composer._isValidDraft()
          expect(status).toBe false
          expect(@dialog.showMessageBox).toHaveBeenCalled()
          dialogArgs = @dialog.showMessageBox.mostRecentCall.args[1]
          expect(dialogArgs.buttons).toEqual ['Send Anyway', 'Cancel']
        )

      it "does not warn if the body of the email is all quoted text, but the email is a forward", ->
        sessionSetupComplete = false
        useDraft.call(@,
          to: [u1]
          subject: "Fwd: Hello World"
          body: "<br><br><blockquote class='gmail_quote'>This is my quoted text!</blockquote>")
        .then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
        runs( =>
          makeComposer.call(@)
          status = @composer._isValidDraft()
          expect(status).toBe true
        )

      it "does not warn if the user has attached a file", ->
        sessionSetupComplete = false
        useDraft.call(@,
          to: [u1]
          subject: "Hello World"
          body: ""
          files: [f1])
        .then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

        runs( =>
          makeComposer.call(@)
          status = @composer._isValidDraft()
          expect(status).toBe true
          expect(@dialog.showMessageBox).not.toHaveBeenCalled()
        )

    it "shows a warning if there's no subject", ->
      sessionSetupComplete = false
      useDraft.call(@, to: [u1], subject: "").then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        status = @composer._isValidDraft()
        expect(status).toBe false
        expect(@dialog.showMessageBox).toHaveBeenCalled()
        dialogArgs = @dialog.showMessageBox.mostRecentCall.args[1]
        expect(dialogArgs.buttons).toEqual ['Send Anyway', 'Cancel']
      )

    it "doesn't show a warning if requirements are satisfied", ->
      sessionSetupComplete = false
      useFullDraft.apply(@).then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        status = @composer._isValidDraft()
        expect(status).toBe true
        expect(@dialog.showMessageBox).not.toHaveBeenCalled()
      )

    describe "Checking for attachments", ->
      warn = (body) ->
        sessionSetupComplete = false
        useDraft.call(@, subject: "Subject", to: [u1], body: body).then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
        runs( =>
          makeComposer.call(@)
          status = @composer._isValidDraft()
          expect(status).toBe false
          expect(@dialog.showMessageBox).toHaveBeenCalled()
          dialogArgs = @dialog.showMessageBox.mostRecentCall.args[1]
          expect(dialogArgs.buttons).toEqual ['Send Anyway', 'Cancel']
        )

      noWarn = (body) ->
        sessionSetupComplete = false
        useDraft.call(@, subject: "Subject", to: [u1], body: body).then( =>
          sessionSetupComplete = true
        )
        waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
        runs( =>
          makeComposer.call(@)
          status = @composer._isValidDraft()
          expect(status).toBe true
          expect(@dialog.showMessageBox).not.toHaveBeenCalled()
        )

      it "warns", -> warn.call(@, "Check out the attached file")
      it "warns", -> warn.call(@, "I've added an attachment")
      it "warns", -> warn.call(@, "I'm going to attach the file")
      it "warns", -> warn.call(@, "Hey attach me <blockquote class='gmail_quote'>sup</blockquote>")

      it "doesn't warn", -> noWarn.call(@, "sup yo")
      it "doesn't warn", -> noWarn.call(@, "Look at the file")
      it "doesn't warn", -> noWarn.call(@, "Hey there <blockquote class='gmail_quote'>attach</blockquote>")

    it "doesn't show a warning if you've attached a file", ->
      sessionSetupComplete = false
      useDraft.call(@,
        subject: "Subject"
        to: [u1]
        body: "Check out attached file"
        files: [f1])
      .then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        status = @composer._isValidDraft()
        expect(status).toBe true
        expect(@dialog.showMessageBox).not.toHaveBeenCalled()
      )

    it "bypasses the warning if force bit is set", ->
      sessionSetupComplete = false
      useDraft.call(@, to: [u1], subject: "").then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        status = @composer._isValidDraft(force: true)
        expect(status).toBe true
        expect(@dialog.showMessageBox).not.toHaveBeenCalled()
      )

    it "sends when you click the send button", ->
      sessionSetupComplete = false
      useFullDraft.apply(@).then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        sendBtn = @composer._els.sendActionButton
        sendBtn.primarySend()
        expect(Actions.sendDraft).toHaveBeenCalledWith(DRAFT_HEADER_MSG_ID, actionKey: 'send')
        expect(Actions.sendDraft.calls.length).toBe 1
        # Delete the draft from _draftsSending so we can send it in other tests
        delete DraftStore._draftsSending[DRAFT_HEADER_MSG_ID]
      )

    it "doesn't send twice if you double click", =>
      sessionSetupComplete = false
      useFullDraft.apply(@).then( =>
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
      runs( =>
        makeComposer.call(@)
        sendBtn = @composer._els.sendActionButton
        sendBtn.primarySend()
        sendBtn.primarySend()
        expect(Actions.sendDraft).toHaveBeenCalledWith(DRAFT_HEADER_MSG_ID, actionKey: 'send')
        expect(Actions.sendDraft.calls.length).toBe 1
        # Delete the draft from _draftsSending so we can send it in other tests
        delete DraftStore._draftsSending[DRAFT_HEADER_MSG_ID]
      )

    describe "when sending a message with keyboard inputs", ->
      beforeEach ->
        sessionSetupComplete = false
        useFullDraft.apply(@).then =>
          makeComposer.call(@)
          @$composer = @composer._els.composerWrap
          sessionSetupComplete = true
          waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

      afterEach ->
        # Delete the draft from _draftsSending so we can send it in other tests
        delete DraftStore._draftsSending[DRAFT_HEADER_MSG_ID]

      it "sends the draft on cmd-enter", ->
        ReactDOM.findDOMNode(@$composer).dispatchEvent(new CustomEvent('composer:send-message'))
        expect(Actions.sendDraft).toHaveBeenCalledWith(DRAFT_HEADER_MSG_ID, actionKey: 'send')
        expect(Actions.sendDraft.calls.length).toBe 1

      it "doesn't let you send twice", ->
        ReactDOM.findDOMNode(@$composer).dispatchEvent(new CustomEvent('composer:send-message'))
        expect(Actions.sendDraft).toHaveBeenCalledWith(DRAFT_HEADER_MSG_ID, actionKey: 'send')
        expect(Actions.sendDraft.calls.length).toBe 1
        ReactDOM.findDOMNode(@$composer).dispatchEvent(new CustomEvent('composer:send-message'))
        expect(Actions.sendDraft).toHaveBeenCalledWith(DRAFT_HEADER_MSG_ID, actionKey: 'send')
        expect(Actions.sendDraft.calls.length).toBe 1

  describe "drag and drop", ->
    beforeEach ->
      sessionSetupComplete = false
      useDraft.call(@,
        to: [u1]
        subject: "Hello World"
        body: ""
        files: [f1])
      .then( =>
        makeComposer.call(@)
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

    describe "_shouldAcceptDrop", ->
      it "should return true if the event is carrying native files", ->
        event =
          dataTransfer:
            files:[{'pretend':'imafile'}]
            types:['Files']
        expect(@composer._shouldAcceptDrop(event)).toBe(true)

      it "should return true if the event is carrying a non-native file URL", ->
        event =
          dataTransfer:
            files:[]
            types:['text/uri-list']
        spyOn(@composer, '_nonNativeFilePathForDrop').andReturn("file://one-file")

        expect(@composer._shouldAcceptDrop(event)).toBe(true)
        expect(@draft.files.length).toBe(1)

      it "should return false otherwise", ->
        event =
          dataTransfer:
            files:[]
            types:['text/plain']
        expect(@composer._shouldAcceptDrop(event)).toBe(false)

    describe "_nonNativeFilePathForDrop", ->
      it "should return a path in the text/nylas-file-url data", ->
        event =
          dataTransfer:
            types: ['text/nylas-file-url']
            getData: -> "image/png:test.png:file:///Users/bengotow/Desktop/test.png"
        expect(@composer._nonNativeFilePathForDrop(event)).toBe("/Users/bengotow/Desktop/test.png")

      it "should return a path in the text/uri-list data", ->
        event =
          dataTransfer:
            types: ['text/uri-list']
            getData: -> "file:///Users/bengotow/Desktop/test.png"
        expect(@composer._nonNativeFilePathForDrop(event)).toBe("/Users/bengotow/Desktop/test.png")

      it "should return null otherwise", ->
        event =
          dataTransfer:
            types: ['text/plain']
            getData: -> "Hello world"
        expect(@composer._nonNativeFilePathForDrop(event)).toBe(null)

      it "should urldecode the contents of the text/uri-list field", ->
        event =
          dataTransfer:
            types: ['text/uri-list']
            getData: -> "file:///Users/bengotow/Desktop/Screen%20shot.png"
        expect(@composer._nonNativeFilePathForDrop(event)).toBe("/Users/bengotow/Desktop/Screen shot.png")

      it "should return null if text/uri-list contains a non-file path", ->
        event =
          dataTransfer:
            types: ['text/uri-list']
            getData: -> "http://apple.com"
        expect(@composer._nonNativeFilePathForDrop(event)).toBe(null)

      it "should return null if text/nylas-file-url contains a non-file path", ->
        event =
          dataTransfer:
            types: ['text/nylas-file-url']
            getData: -> "application/json:filename.json:undefined"
        expect(@composer._nonNativeFilePathForDrop(event)).toBe(null)

  describe "A draft with files (attachments)", ->
    beforeEach ->
      @file1 = new File
        id: "f_1"
        filename: "f1.pdf"
        size: 1230

      @file2 = new File
        id: "f_2"
        filename: "f2.jpg"
        size: 4560

      @file3 = new File
        id: "f_3"
        filename: "f3.png"
        size: 7890

      spyOn(Actions, "fetchFile")

      sessionSetupComplete = false
      useDraft.call(@, files: [@file1, @file2]).then( =>
        makeComposer.call(@)
        sessionSetupComplete = true
      )
      waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)

    it 'starts fetching attached files', ->
      waitsFor ->
        Actions.fetchFile.callCount == 1
      runs ->
        expect(Actions.fetchFile).toHaveBeenCalled()
        expect(Actions.fetchFile.calls.length).toBe(1)
        expect(Actions.fetchFile.calls[0].args[0]).toBe @file2

    it 'renders a AttachmentItem for any present attachments', ->
      els = ReactTestUtils.scryRenderedComponentsWithTypeAndProps(@composer, AttachmentItem, {})
      expect(els.length).toBe 1
      expect(els[0].props.displayName).toEqual(@draft.files[0].filename)

    it 'renders an ImageAttachmentItem for any attachments that look like images', ->
      els = ReactTestUtils.scryRenderedComponentsWithTypeAndProps(@composer, ImageAttachmentItem, {})
      expect(els.length).toBe 1
      expect(els[0].props.displayName).toEqual(@draft.files[1].filename)

describe "when a file is received (via drag and drop or paste)", ->
  beforeEach ->
    sessionSetupComplete = false
    useDraft.call(@).then( =>
      sessionSetupComplete = true
    )
    waitsFor(( => sessionSetupComplete), "The session's draft needs to be set", 500)
    runs( =>
      makeComposer.call(@)
      @file = new File({size: 1000, filename: 'f.txt', id: 'f'})
      spyOn(Actions, 'addAttachment').andCallFake ({filePath, messageId, onCreated}) =>
        @draft.files.push(@file)
        onCreated(@file)
      spyOn(Actions, 'insertAttachmentIntoDraft')
    )

  it "should call addAttachment with the path and id", ->
    @composer._onFileReceived('../../f.txt')
    expect(Actions.addAttachment.callCount).toBe(1)
    expect(Object.keys(Actions.addAttachment.calls[0].args[0])).toEqual([
      'filePath', 'headerMessageId', 'onCreated',
    ])

  it "should call insertAttachmentIntoDraft if the file looks like an image", ->
    @file = new File({size: 1000, filename: 'f.txt', id: 'f'})
    @composer._onFileReceived('../../f.txt')
    advanceClock()
    expect(Actions.insertAttachmentIntoDraft).not.toHaveBeenCalled()
    expect(!!@file.contentId).not.toEqual(true)

    @file = new File({size: 1000, filename: 'f.png', id: 'g'})
    expect(Utils.shouldDisplayAsImage(@file)).toBe(true) # sanity check

    @composer._onFileReceived('../../f.png')
    advanceClock()
    expect(Actions.insertAttachmentIntoDraft).toHaveBeenCalled()
    expect(!!@file.contentId).toEqual(true)

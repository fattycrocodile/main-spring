Actions = require('../src/flux/actions').default
Message = require('../src/flux/models/message').default
AccountStore = require('../src/flux/stores/account-store').default
ActionBridge = require('../src/flux/action-bridge').default
_ = require 'underscore'

ipc =
    on: ->
    send: ->

describe "ActionBridge", ->

  describe "in the main window", ->
    beforeEach ->
      spyOn(AppEnv, "getWindowType").andReturn "default"
      spyOn(AppEnv, "isMainWindow").andReturn true
      @bridge = new ActionBridge(ipc)

    it "should have the role Role.MAIN", ->
      expect(@bridge.role).toBe(ActionBridge.Role.MAIN)

    it "should rebroadcast global actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.globalActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should not rebroadcast mainWindow actions since it is the main window", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions.queueTask
      testAction('bla')
      expect(@bridge.onRebroadcast).not.toHaveBeenCalled()

    it "should not rebroadcast window actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.windowActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).not.toHaveBeenCalled()

  describe "in another window", ->
    beforeEach ->
      spyOn(AppEnv, "getWindowType").andReturn "popout"
      spyOn(AppEnv, "isMainWindow").andReturn false
      @bridge = new ActionBridge(ipc)
      @message = new Message
        id: 'test-id'
        accountId: TEST_ACCOUNT_ID

    it "should have the role Role.SECONDARY", ->
      expect(@bridge.role).toBe(ActionBridge.Role.SECONDARY)

    it "should rebroadcast global actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.globalActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should rebroadcast mainWindow actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions.queueTask
      testAction('bla')
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should not rebroadcast window actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.windowActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).not.toHaveBeenCalled()

  describe "onRebroadcast", ->
    beforeEach ->
      spyOn(AppEnv, "getWindowType").andReturn "popout"
      spyOn(AppEnv, "isMainWindow").andReturn false
      @bridge = new ActionBridge(ipc)

    describe "when called with TargetWindows.ALL", ->
      it "should broadcast the action over IPC to all windows", ->
        spyOn(ipc, 'send')
        Actions.openPreferences.firing = false
        @bridge.onRebroadcast(ActionBridge.TargetWindows.ALL, 'openPreferences', [{oldModel: '1', newModel: 2}])
        expect(ipc.send).toHaveBeenCalledWith('action-bridge-rebroadcast-to-all', 'popout', 'openPreferences', '[{"oldModel":"1","newModel":2}]')

    describe "when called with TargetWindows.MAIN", ->
      it "should broadcast the action over IPC to the main window only", ->
        spyOn(ipc, 'send')
        Actions.openPreferences.firing = false
        @bridge.onRebroadcast(ActionBridge.TargetWindows.MAIN, 'openPreferences', [{oldModel: '1', newModel: 2}])
        expect(ipc.send).toHaveBeenCalledWith('action-bridge-rebroadcast-to-default', 'popout', 'openPreferences', '[{"oldModel":"1","newModel":2}]')

    it "should not do anything if the current invocation of the Action was triggered by itself", ->
      spyOn(ipc, 'send')
      Actions.openPreferences.firing = true
      @bridge.onRebroadcast(ActionBridge.TargetWindows.ALL, 'openPreferences', [{oldModel: '1', newModel: 2}])
      expect(ipc.send).not.toHaveBeenCalled()

{find} = require 'underscore-plus'
{Model} = require 'theorist'
{Emitter, CompositeDisposable} = require 'event-kit'
Serializable = require 'serializable'
Pane = require './pane'

module.exports =
class PaneContainer extends Model
  atom.deserializers.add(this)
  Serializable.includeInto(this)

  @version: 1

  @properties
    activePane: null

  root: null

  @behavior 'activePaneItem', ->
    @$activePane
      .switch((activePane) -> activePane?.$activeItem)
      .distinctUntilChanged()

  constructor: (params) ->
    super

    @emitter = new Emitter
    @subscriptions = new CompositeDisposable

    @setRoot(params?.root ? new Pane)
    @destroyEmptyPanes() if params?.destroyEmptyPanes

    @monitorActivePaneItem()

  deserializeParams: (params) ->
    params.root = atom.deserializers.deserialize(params.root, container: this)
    params.destroyEmptyPanes = atom.config.get('core.destroyEmptyPanes')
    params.activePane = params.root.getPanes().find (pane) -> pane.id is params.activePaneId
    params

  serializeParams: (params) ->
    root: @root?.serialize()
    activePaneId: @activePane.id

  onDidChangeRoot: (fn) ->
    @emitter.on 'did-change-root', fn

  observeRoot: (fn) ->
    fn(@getRoot())
    @onDidChangeRoot(fn)

  onDidChangeActivePane: (fn) ->
    @emitter.on 'did-change-active-pane', fn

  observeActivePane: (fn) ->
    fn(@getActivePane())
    @onDidChangeActivePane(fn)

  onDidChangeActivePaneItem: (fn) ->
    @emitter.on 'did-change-active-pane-item', fn

  observeActivePaneItem: (fn) ->
    fn(@getActivePaneItem())
    @onDidChangeActivePaneItem(fn)

  getRoot: -> @root

  setRoot: (@root) ->
    @root.parent = this
    @root.container = this
    @emitter.emit 'did-change-root', @root
    if not @getActivePane()? and @root instanceof Pane
      @setActivePane(@root)

  replaceChild: (oldChild, newChild) ->
    throw new Error("Replacing non-existent child") if oldChild isnt @root
    @setRoot(newChild)

  getPanes: ->
    @getRoot().getPanes()

  getActivePane: ->
    @activePane

  setActivePane: (activePane) ->
    if activePane isnt @activePane
      @activePane = activePane
      @emitter.emit 'did-change-active-pane', @activePane
    @activePane

  getActivePaneItem: ->
    @getActivePane().getActiveItem()

  paneForUri: (uri) ->
    find @getPanes(), (pane) -> pane.itemForUri(uri)?

  saveAll: ->
    pane.saveItems() for pane in @getPanes()

  activateNextPane: ->
    panes = @getPanes()
    if panes.length > 1
      currentIndex = panes.indexOf(@activePane)
      nextIndex = (currentIndex + 1) % panes.length
      panes[nextIndex].activate()
      true
    else
      false

  activatePreviousPane: ->
    panes = @getPanes()
    if panes.length > 1
      currentIndex = panes.indexOf(@activePane)
      previousIndex = currentIndex - 1
      previousIndex = panes.length - 1 if previousIndex < 0
      panes[previousIndex].activate()
      true
    else
      false

  destroyEmptyPanes: ->
    pane.destroy() for pane in @getPanes() when pane.items.length is 0

  itemDestroyed: (item) ->
    @emit 'item-destroyed', item

  # Called by Model superclass when destroyed
  destroyed: ->
    pane.destroy() for pane in @getPanes()
    @subscriptions.dispose()
    @emitter.dispose()

  monitorActivePaneItem: ->
    childSubscription = null
    @subscriptions.add @observeActivePane (activePane) =>
      if childSubscription?
        @subscriptions.remove(childSubscription)
        childSubscription.dispose()

      childSubscription = activePane.observeActiveItem (activeItem) =>
        @emitter.emit 'did-change-active-pane-item', activeItem

      @subscriptions.add(childSubscription)

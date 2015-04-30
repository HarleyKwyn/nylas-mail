_ = require 'underscore-plus'
ipc = require 'ipc'
React = require 'react/addons'
{DatabaseStore,
 NamespaceStore,
 TaskQueue,
 Actions,
 Contact,
 Message} = require 'inbox-exports'
{ResizableRegion} = require 'ui-components'

ActivityBarStore = require './activity-bar-store'
ActivityBarTask = require './activity-bar-task'
ActivityBarCurlItem = require './activity-bar-curl-item'
ActivityBarLongPollItem = require './activity-bar-long-poll-item'

ActivityBarClosedHeight = 30

class ActivityBar extends React.Component
  @displayName: "ActivityBar"

  constructor: (@props) ->
    @state = _.extend @_getStateFromStores(),
      height: ActivityBarClosedHeight
      section: 'curl'
      filter: ''

  componentDidMount: =>
    ipc.on 'report-issue', => @_onFeedback()
    @taskQueueUnsubscribe = TaskQueue.listen @_onChange
    @activityStoreUnsubscribe = ActivityBarStore.listen @_onChange

  componentWillUnmount: =>
    @taskQueueUnsubscribe() if @taskQueueUnsubscribe
    @activityStoreUnsubscribe() if @activityStoreUnsubscribe

  render: =>
    return <div></div> unless @state.visible

    <ResizableRegion className="activity-bar"
                     initialHeight={@state.height}
                     minHeight={ActivityBarClosedHeight}
                     handle={ResizableRegion.Handle.Top}>
      <div className="controls">
        {@_caret()}
        <div className="btn-container pull-left">
          <div className="btn" onClick={ => @_onExpandSection('queue')}>
            <span>Queue Length: {@state.queue?.length}</span>
          </div>
        </div>
        <div className="btn-container pull-left">
          <div className="btn" onClick={ => @_onExpandSection('long-polling')}>
            <div className={"activity-status-bubble state-" + @state.longPollState}></div>
            <span>Long Polling: {@state.longPollState}</span>
          </div>
        </div>
        <div className="btn-container pull-left">
          <div className="btn" onClick={ => @_onExpandSection('curl')}>
            <span>Requests: {@state.curlHistory.length}</span>
          </div>
        </div>
        <div className="btn-container pull-right">
          <div className="btn" onClick={@_onFeedback}>Feedback</div>
        </div>
        <div className="btn-container pull-right">
          <div className="btn" onClick={@_onToggleRegions}>Component Regions</div>
        </div>
      </div>
      {@_sectionContent()}
      <div className="footer">
        <div className="btn" onClick={@_onClear}>Clear</div>
        <input className="filter" placeholder="Filter..." value={@state.filter} onChange={@_onFilter} />
      </div>
    </ResizableRegion>

  _caret: =>
    if @state.height > ActivityBarClosedHeight
      <i className="fa fa-caret-square-o-down" onClick={@_onHide}></i>
    else
      <i className="fa fa-caret-square-o-up" onClick={@_onShow}></i>

  _sectionContent: =>
    expandedDiv = <div></div>

    matchingFilter = (item) =>
      return true if @state.filter is ''
      return JSON.stringify(item).indexOf(@state.filter) >= 0

    if @state.section == 'curl'
      itemDivs = @state.curlHistory.filter(matchingFilter).map (item) ->
        <ActivityBarCurlItem item={item}/>
      expandedDiv = <div className="expanded-section curl-history">{itemDivs}</div>

    else if @state.section == 'long-polling'
      itemDivs = @state.longPollHistory.filter(matchingFilter).map (item) ->
        <ActivityBarLongPollItem item={item} key={item.cursor}/>
      expandedDiv = <div className="expanded-section long-polling">{itemDivs}</div>

    else if @state.section == 'queue'
      queue = @state.queue.filter(matchingFilter)
      queueDivs = for i in [@state.queue.length - 1..0] by -1
        task = @state.queue[i]
        <ActivityBarTask task=task
                         key=task.id
                         type="queued" />

      queueCompleted = @state.completed.filter(matchingFilter)
      queueCompletedDivs = for i in [@state.completed.length - 1..0] by -1
        task = @state.completed[i]
        <ActivityBarTask task=task
                         key=task.id
                         type="completed" />

      expandedDiv =
        <div className="expanded-section queue">
          <div className="btn queue-buttons"
               onClick={@_onDequeueAll}>Remove Queued Tasks</div>
          <div className="section-content">
            {queueDivs}
            <hr />
            {queueCompletedDivs}
          </div>
        </div>

      expandedDiv

  _onChange: =>
    @setState(@_getStateFromStores())

  _onClear: =>
    Actions.clearDeveloperConsole()

  _onFilter: (ev) =>
    @setState(filter: ev.target.value)

  _onDequeueAll: =>
    Actions.dequeueAllTasks()

  _onHide: =>
    @setState
      height: ActivityBarClosedHeight

  _onShow: =>
    @setState(height: 200) if @state.height < 100

  _onExpandSection: (section) =>
    @setState(section: section)
    @_onShow()

  _onToggleRegions: =>
    Actions.toggleComponentRegions()

  _onFeedback: =>
    user = NamespaceStore.current().name

    debugData = JSON.stringify({
      queries: @state.curlHistory,
      queue: @state.queue,
      completed: @state.completed
    }, null, '\t')

    # Remove API tokens from URLs included in the debug data
    # This regex detects ://user:pass@ and removes it.
    debugData = debugData.replace(/:\/\/(\w)*:(\w)?@/g, '://')

    draft = new Message
      from: [NamespaceStore.current().me()]
      to: [
        new Contact
          name: "Nilas Team"
          email: "feedback@nilas.com"
      ]
      date: (new Date)
      draft: true
      subject: "Feedback"
      namespaceId: NamespaceStore.current().id
      body: """
        Hi, Edgehill team! I have some feedback for you.<br/>
        <br/>
        <b>What happened:</b><br/>
        <br/>
        <br/>
        <b>Impact:</b><br/>
        <br/>
        <br/>
        <b>Feedback:</b><br/>
        <br/>
        <br/>
        <b>Environment:</b><br/>
        I'm using Edgehill #{atom.getVersion()} and my platform is #{process.platform}-#{process.arch}.<br/>
        --<br/>
        #{user}<br/>
        -- Extra Debugging Data --<br/>
        #{debugData}
      """
    DatabaseStore.persistModel(draft).then ->
      DatabaseStore.localIdForModel(draft).then (localId) ->
        Actions.composePopoutDraft(localId)

  _getStateFromStores: =>
    visible: ActivityBarStore.visible()
    queue: TaskQueue._queue
    completed: TaskQueue._completed
    curlHistory: ActivityBarStore.curlHistory()
    longPollHistory: ActivityBarStore.longPollHistory()
    longPollState: ActivityBarStore.longPollState()


module.exports = ActivityBar

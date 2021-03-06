Backoff        = require 'backo'
_              = require 'lodash'
EventEmitter2  = require 'eventemitter2'
SocketIOClient = require 'socket.io-client'
SrvFailover    = require 'srv-failover'
URL            = require 'url'

WRONG_SERVER_ERROR = '"identify" received. Likely connected to meshblu-socket-io instead of the meshblu-firehose-socket-io'

class MeshbluFirehoseSocketIO extends EventEmitter2
  @FORWARD_EVENTS = [
    'connect'
    'connect_error'
    'connect_timeout'
    'disconnect'
    'reconnect'
    'reconnect_error'
    'reconnect_failed'
    'upgrade'
    'upgradeError'
  ]

  constructor: ({meshbluConfig, @transports, @srvFailover}) ->
    super wildcard: true

    throw new Error('MeshbluFirehoseSocketIO: meshbluConfig is required') unless meshbluConfig?
    throw new Error('MeshbluFirehoseSocketIO: meshbluConfig.uuid is required') unless meshbluConfig.uuid?
    throw new Error('MeshbluFirehoseSocketIO: meshbluConfig.token is required') unless meshbluConfig.token?

    @backoff = new Backoff

    {uuid, token}              = meshbluConfig
    {protocol, hostname, port} = meshbluConfig
    {service, domain, secure}  = meshbluConfig
    {resolveSrv}               = meshbluConfig

    if resolveSrv
      @_assertNoUrl {protocol, hostname, port}
      domain  ?= 'octoblu.com'
      service ?= 'meshblu-firehose'
      srvProtocol = 'socket-io-wss'
      urlProtocol = 'wss'
      if secure == false
        srvProtocol = 'socket-io-ws'
        urlProtocol = 'ws'
      @srvFailover ?= new SrvFailover {domain, service, protocol: srvProtocol, urlProtocol}
    else
      @_assertNoSrv {service, domain, secure}
      protocol ?= 'https'
      hostname ?= 'meshblu-firehose-socket-io.octoblu.com'
      port     ?= 443

    @meshbluConfig = {uuid, token, resolveSrv, protocol, hostname, port, service, domain, secure}

  connect: (callback) =>
    throw new Error 'connect should not take a callback' if callback?

    @closing = false
    @emit 'connecting'

    @_resolveBaseUrl (error, baseUrl) =>
      if error?
        @emit 'resolve-base-url:error', error
        return @_reconnect()

      options =
        path: "/socket.io/v1/#{@meshbluConfig.uuid}"
        reconnection: false
        extraHeaders:
          'X-Meshblu-UUID': @meshbluConfig.uuid
          'X-Meshblu-Token': @meshbluConfig.token
        query:
          uuid: @meshbluConfig.uuid
          token: @meshbluConfig.token
        transports: @transports

      @socket = SocketIOClient baseUrl, options

      @socket.once 'identify', =>
        @emit 'error', new Error(WRONG_SERVER_ERROR)

      @socket.once 'connect', =>
        @backoff.reset()

      @socket.once 'disconnect', =>
        return if @closing
        @_reconnect()

      @socket.once 'connect_error', =>
        @srvFailover.markBadUrl baseUrl, ttl: 60000 if @srvFailover?
        @_reconnect()

      @bindEvents()

  _reconnect: =>
    @emit 'reconnecting'
    _.delay @connect, @backoff.duration()

  bindEvents: =>
    @socket.on 'message', @_onMessage

    @socket.on 'error', =>
      @emit 'socket-io:error', arguments...

    @socket.on 'close', =>
      @emit 'socket-io:close', arguments...

    _.each MeshbluFirehoseSocketIO.FORWARD_EVENTS, (event) =>
      @socket.on event, =>
        @emit event, arguments...

  close: (callback=->) =>
    @closing = true
    @socket.once 'disconnect', => callback()
    @socket.disconnect()

  _assertNoSrv: ({service, domain, secure}) =>
    throw new Error('domain parameter is only valid when the parameter resolveSrv is true')  if domain?
    throw new Error('service parameter is only valid when the parameter resolveSrv is true') if service?
    throw new Error('secure parameter is only valid when the parameter resolveSrv is true')  if secure?

  _assertNoUrl: ({protocol, hostname, port}) =>
    throw new Error('protocol parameter is only valid when the parameter resolveSrv is false') if protocol?
    throw new Error('hostname parameter is only valid when the parameter resolveSrv is false') if hostname?
    throw new Error('port parameter is only valid when the parameter resolveSrv is false')     if port?

  _emitWithRoute: (message) =>
    hop = _.first(message.metadata.route)
    return unless hop?
    {from, type} = hop
    channel = "#{type}.#{from}"
    @emit channel, message

  _onMessage: (message) =>
    newMessage =
      metadata: message.metadata

    try
      newMessage.data = JSON.parse message.rawData
    catch
      newMessage.rawData = message.rawData

    @emit 'message', newMessage

    @_emitWithRoute newMessage

  _resolveBaseUrl: (callback) =>
    return callback null, @_resolveNormalUrl() unless @meshbluConfig.resolveSrv
    return @srvFailover.resolveUrl (error, baseUrl) =>
      if error && error.noValidAddresses
        @srvFailover.clearBadUrls()
        return @_resolveBaseUrl callback
      return callback error if error?
      return callback null, baseUrl

  _resolveNormalUrl: =>
    {protocol, hostname, port} = @meshbluConfig

    protocol ?= 'ws'
    protocol  = 'wss' if port == 443

    URL.format {protocol, hostname, port, slashes: true}


module.exports = MeshbluFirehoseSocketIO

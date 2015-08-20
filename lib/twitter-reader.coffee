{Disposable, CompositeDisposable} = require 'atom'

TwitterTransport = require "./twitter-transport"
TwitterReaderView = require './twitter-reader-view'

# atom.deserializers.add
#     name : "TwitterReaderView"
#     deserialize : (state) ->
#         trns = new TwitterTransport(state)
#         new TwitterReaderView(trns)

module.exports = TwitterReader =
    config      :
        "consumer_key"  :
            title   : "Twitter consumer key"
            type    : "string"
            default : ""
            order   : 1

        "consumer_secret"  :
            title   : "Twitter consumer secret"
            type    : "string"
            default : ""
            order   : 2

        "access_token_key" :
            title   : "Twitter access token key"
            type    : "string"
            default : ""
            order   : 3

        "access_token_secret" :
            title   : "Twitter access token secret"
            type    : "string"
            default : ""
            order   : 4

    activate: (state) ->
        @subscriptions = new CompositeDisposable

        @subscriptions.add atom.workspace.addOpener (uri) =>
            return unless uri.startsWith("twitter://")
            new TwitterReaderView(new TwitterTransport())

        @subscriptions.add atom.commands.add 'atom-workspace',
            'twitter-reader:show': => atom.workspace.open("twitter://", {split: "right"})

        @subscriptions.add new Disposable =>
            console.log "dispose!"


    deactivate: ->
        console.info "deactivated"
        @subscriptions.dispose()
        @twitterReaderView.destroy()

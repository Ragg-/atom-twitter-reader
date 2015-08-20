{CompositeDisposable, Disposable} = require "atom"
EventEmitter = require "eventemitter3"
Twitter = require "twitter"

module.exports =
class TwitterTranport extends EventEmitter
    constructor : ->
        @disposables = new CompositeDisposable()
        @initDefer = Promise.defer()

        @twitter = new Twitter
            consumer_key        : atom.config.get("twitter-reader.consumer_key"),
            consumer_secret     : atom.config.get("twitter-reader.consumer_secret"),
            access_token_key    : atom.config.get("twitter-reader.access_token_key"),
            access_token_secret : atom.config.get("twitter-reader.access_token_secret"),

        # Fetch access user infomation
        @twitter.get "account/verify_credentials", {}, (err, info, raw) =>
            return @initDefer.reject(err) if err?
            @currentUser = info
            @initDefer.resolve()

    dispose : ->
        @disposables.dispose()

    getUserProfile : ->
        @currentUser

    fetchHomeAndReplies : (homeOpt, replyOpt) ->
        defer = Promise.defer()

        Promise.all([@fetchHomeTimeLine(homeOpt), @fetchReplies(replyOpt)])
            .then ([homeTweets, replies]) ->
                tweets = []
                tweets.push.apply tweets, homeTweets
                tweets.push.apply tweets, replies
                tweets.sort (tweetA, tweetB) ->
                    tweetB.id_str - tweetA.id_str

                defer.resolve(tweets)

        defer.promise

    fetchHomeTimeLine : (options) ->
        defer = Promise.defer()

        @twitter.get "statuses/home_timeline", options, (err, tweets, res) =>
            return defer.reject(err) if err?
            tweets = tweets.map(@_processTweetData, @)
            defer.resolve(tweets)

        defer.promise

    fetchReplies : (options) ->
        defer = Promise.defer()

        @twitter.get "statuses/mentions_timeline", options, (err, tweets) =>
            return defer.reject(err) if err?
            tweets = tweets.map(@_processTweetData, @)
            defer.resolve(tweets)

        defer.promise

    _processTweetData : (tweet) ->
        tweet.__ = {}

        if tweet.retweeted_status
            tweet.retweeted_status = @_processTweetData(tweet.retweeted_status)

        # tweet is reply to me?
        for mention in tweet.entities.user_mentions
            continue unless mention.id_str is @currentUser.id_str
            tweet.__.replyToMe = true
            break

        tweet

    startUserStreamListening : (option = {}) ->
        defer = Promise.defer()

        @twitter.stream "user", option, (stream) =>
            @twStream = stream

            @disposables.add new Disposable =>
                @stopUserStreamListening()

            stream.on "error", (e) =>
                defer.reject()
                @emit "error", e

            stream.on "end", =>
                @emit "did-end-stream"

            stream.on "data", (data) =>
                return if data.friends? and not data.text?
                return @emit("did-receive-deletion", data) if data.delete?

                data = @_processTweetData(data)
                @emit "did-receive-tweet", data

            stream.on "favorite", (data) =>
                @emit "did-receive-favorite", data

            stream.on "unfavorite", (data) =>
                @emit "did-receive-unfavorite", data

            defer.resolve()

        defer.promise

    stopUserStreamListening : ->
        @twStream?.removeAllListeners()
        @twStream?.destroy()
        @twStream = null
        return

    fetchTweetInfo : (statusId) ->
        defer = Promise.defer()

        @twitter.get "statuses/show/#{statusId}", {}, (err, tweet) =>
            return defer.reject(err) if err?
            defer.resolve @_processTweetData(tweet)

        defer.promise

    tweet : (params) ->
        new Promise (resolve, reject) =>
            @twitter.post "statuses/update", params, (err, res) =>
                return reject(err) if err?

                resolve(res)
                @emit "did-ship-tweet", res

    favorite : (statusId) ->
        new Promise (resolve, reject) =>
            @twitter.post "favorites/create", {id: statusId}, (err, res) =>
                return reject(err) if err?

                resolve(res)
                @emit "did-favorite", res

    retweet : (statusId) ->
        new Promise (resolve, reject) =>
            @twitter.post "statuses/retweet/#{statusId}", {}, (err, res) =>
                return reject(err) if err?

                resolve(res)
                @emit "did-retweet", res


    # Events

    on : (event, listener) ->
        super event, listener
        new Disposable => @off event, listener

    onDidShipTweet : (callback) -> @on "did-ship-tweet", callback

    onDidReceiveTweet : (callback) -> @on "did-receive-tweet", callback

    onDidDeleteTweet : (callback) -> @on "did-receive-deletion", callback

    onDidReceiveFavorite : (callback) -> @on "did-receive-favorite", callback

    onDidReceiveUnFavorite : (callback) -> @on "did-receive-unfavorite", callback

    onDidCatchError   : (callback) -> @on "error", callback

    onDidInitialize : (callback) -> @initDefer.promise.then callback

    onDidEndStream : (callback) -> @on "did-end-stream", callback

{CompositeDisposable, Disposable} = require "atom"
{ScrollView, $, $$} = require 'atom-space-pen-views'
_ = require "lodash"
Moment = require "moment"
osLocale = require "os-locale"

Twitter = require "twitter"

twitter = null
twStream = null

module.exports =
class TwitterReaderView extends ScrollView
    @content : ->
        @div class: "twitter-reader", tabindex: -1, =>
            @form class: "post native-key-bindings", outlet: "postPanel", tabindex: -1
            @ul class: "timeline native-key-bindings", outlet: "tlList", tabindex: -1
            @div class: "mediaview", outlet: "mediaView", =>
                @div class: "mediaview_arrow"
                @div class: "mediaview_content", outlet: "mediaViewContent"

    constructor : (twitter) ->
        super
        @disposables = new CompositeDisposable
        @twitter = twitter

        osLocale (er, locale) ->
            Moment.locale(locale)

        @twitter.onDidInitialize =>
            @initUserPanel(@twitter.getUserProfile())

        @twitter.fetchHomeTimeLine({count: 100})
            .then (tweets) =>
                tweets
                    .reverse()
                    .splice(0, 200)
                    .forEach @displayTweet.bind(@)

                do =>
                    fn = arguments.callee
                    @twitter.startUserStreamListening().catch =>
                        console.warn "Failed to listen twitter UserStream, Retry connect to 2seconds"
                        setTimeout fn, 2000
            .then =>
                @handleEvents()

        window.addEventListener "unload", =>
            @destroy()
            return

    handleEvents : ->
        @disposables.add @twitter.onDidReceiveTweet(@displayTweet.bind(@))
        @disposables.add @twitter.onDidReceiveFavorite(@hasBeenFavorite.bind(@))
        @disposables.add @twitter.onDidReceiveFavorite(@markFavorite.bind(@))
        @disposables.add @twitter.onDidReceiveUnFavorite(@removeFavorited.bind(@))
        @disposables.add @twitter.onDidReceiveUnFavorite(@unmarkFavorite.bind(@))
        @disposables.add @twitter.onDidDeleteTweet(@receiveTweetDeletion.bind(@))

        # Update tweet ago times
        @disposables.add new Disposable do =>
            intervalId = setInterval =>
                for el in @tlList[0].children
                    timesAgo = Moment(new Date(el.dataset.tweetedAt)).fromNow()
                    $(el).find(".tweet_times-ago").text(timesAgo)
            , 5000

            return -> clearInterval intervalId

        # # Retry connection on stream ended
        # @disposables.add @twitter.onDidEndStream =>
        #     console.error "Twitter stream ended"

        @disposables.add @twitter.onDidCatchError (e) =>
            console.error "TwitterReader error", e

        # Delegate Cmd(orCtrl)+Enter to form submit
        @postPanel.on "keydown", (e) =>
            # (Ctrl or Cmd) + Enter
            if (e.metaKey or e.ctrlKey) and e.keyCode is 13
                @postPanel.submit()
                return

        # Clear reply to status when textarea empty
        @postPanel.on "keyup keydown", ".post_input", (e) ->
            if @value.trim().length is 0
                delete @dataset["replyToStatus"]

        # Tweet
        @postPanel.on "submit", (e) =>
            $bt = $(@).find(".post_submit")
            $ta = $(@).find(".post_input")

            bt = $bt[0]
            ta = $ta[0]

            params = {}
            params["status"] = $ta.val()
            params["in_reply_to_status_id"] = ta.dataset.replyToStatus if ta.dataset.replyToStatus?

            bt.disabled = true
            ta.disabled = true

            @twitter.tweet(params).then ->
                ta.disabled = false
                bt.disabled = false

                ta.value = ""
                delete ta.dataset.replyToStatus

            return false

        # Stop open actions panel while scrolling
        @tlList.on "scroll", do =>
            timerId = null

            return =>
                unless @tlList.is(".timeline--scrolling")
                    clearTimeout timerId if timerId?

                    @tlList.addClass "timeline--scrolling"

                    timerId = setTimeout =>
                        @tlList.removeClass "timeline--scrolling"
                    , 500
                return

        # Handle actions for tweet
        @tlList.on "click", "[data-action]", (e) =>
            action = e.target.dataset.action
            $tweetItem = $(e.currentTarget).parents(".tweet:first")

            console.log e.currentTarget, $tweetItem

            statusId = $tweetItem.attr("data-status-id")
            tweeterId = $tweetItem.attr("data-tweeter-screen-name")

            switch action
                when "reply"
                    $text = @postPanel.find(".post_input")
                    $text.attr "data-reply-to-status", statusId
                    $text.val "@#{tweeterId} "
                    $text.focus()

                when "fav"
                    @twitter.favorite(statusId).then (res) ->

                when "retweet"
                    @twitter.retweet(statusId).then (res) ->

                when "paste_link"
                    $text = @postPanel.find(".post_input")
                    value = $text.val()
                    value.length isnt 0 and (value += "\n")
                    value += "https://twitter.com/#{tweeterId}/status/#{statusId}"
                    $text.val(value)

        # Handle extended media mouse over
        # (Open media view pane)
        @tlList.on "mouseenter", ".tweet_ex-media", (e) =>
            self = @
            el = e.currentTarget
            $el = $(el)

            if ($content = $el.find(".tweet_ex-media_img")).length
                @mediaViewContent.empty().append $$ ->
                    @a href: $el.attr("href"), =>
                        @img class:"mediaview_content_image", src: $content.attr("src")

            else if $el.is(".tweet")
                return

            @mediaView
                .css("top", $content.offset().top + $content.height() / 2)

            @mediaView.find(".mediaview_arrow")
                .css("left", $content[0].offsetLeft + ($content.width() / 2))

        do =>
            mediaHovered = false
            viewHovered = false

            updateDisplay = =>
                @mediaView.off "webkitTransitionEnd"

                if mediaHovered or viewHovered
                    @mediaView
                        .show()
                        .addClass "mediaview--open"
                else
                    @mediaView
                        .one "webkitTransitionEnd", => @mediaView.hide()
                        .removeClass "mediaview--open"

            @tlList.on "mouseenter mousemove", ".tweet_ex-media", ->
                mediaHovered = true
                updateDisplay()

            @tlList.on "mouseleave", ".tweet_ex-media", ->
                mediaHovered = false
                updateDisplay()

            @mediaView.on "mouseenter mousemove", ->
                viewHovered  = true
                updateDisplay()

            @mediaView.on "mouseleave", ->
                viewHovered = false
                updateDisplay()

        return

    initUserPanel : (prof) ->
        @postPanel.empty().append $$ ->
            @span class: "post_account", =>
                @img class: "post_account_avator", src: prof.profile_image_url
                # @strong class: "post_account_user-name", => @text prof.name
                # @span class: "post_account_screen-name", => @text "@#{prof.screen_name}"
            @textarea class: "post_input native-key-bindings"
            @button class: "post_submit btn btn-primary btn-sm", => @text "tweet"

        return


    # Tweet item construction

    _processEntities : (text, entitiesObj) ->
        escapedRegExp = (string, pattern) ->
            string = string.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
            if pattern?
                new RegExp(string.replace(/(^.*$)/, pattern))
            else
                new RegExp(string)

        e = (string) ->
            htmlEscapes =
                "&": "&amp;"
                "<": "&lt;"
                ">": "&gt;"
                """: "&quot;"
                """: "&#39;"
                "`": "&#96;"
            string.replace /[&<>"'`]/g, (c) -> htmlEscapes[c]

        for type, entities of entitiesObj
            switch type
                when "user_mentions" then for entity in entities
                    text = text.replace(escapedRegExp("@#{entity.screen_name}", "($1)"), "<span class='tweet_mention'>$1</span>")

                when "hashtags" then for entity in entities
                    text = text.replace(escapedRegExp("##{entity.text}", "($1)"), "<span class='tweet_hashtag'>##{e(entity.text)}</span>")

                when "urls" then for entity in entities
                    if entity.display_url.match(/^twitter\.com\//)
                        text = text.replace(escapedRegExp("#{entity.url}", "$1"), "")
                    else
                        text = text.replace(escapedRegExp("#{entity.url}", "($1)"), "<a target='_blank' href='#{e(entity.expanded_url)}'>#{e(entity.display_url)}</a>")

                when "media" then for entity in entities
                    text = text.replace(escapedRegExp("#{entity.url}", "($1)"), "<a target='_blank' href='#{entity.media_url}'>#{entity.url}</a>")

        text

    _buildExtendedEntities : (viewCtx, tweet) ->
        fnQue = []
        self = @
        exEntities = tweet.extended_entities

        # return [] unless exEntities?.media?

        # process quoted tweet
        if tweet.quoted_status? then fnQue.push ->
            self._buildQuotedTweet(@, tweet.quoted_status)

        # process imaget
        if exEntities?.media? then fnQue.push ->
            for entity in exEntities.media
                continue unless entity.type is "photo"

                @a class: "tweet_ex-media", href: entity.expanded_url, =>
                    @img class: "tweet_ex-media_img", src: entity.media_url

        if fnQue.length > 0
            fn = ->
                @aside class: "tweet_extended", =>
                    fnQue.forEach (render) -> render.call(viewCtx)

            fn.call viewCtx

    _buildTweetAccountHeader : (viewCtx, tweeter, retweeter = null, {noAvator} = {}) ->
        if retweeter?
            fn = (tweeter, retweeter) ->
                @div class: "tweet_account", =>
                    @div class: "tweet_account_avator tweet_account_avator--retweet", =>
                        if noAvator isnt true
                            @a target: "_blank", href: "https://twitter.com/#{tweeter.screen_name}", =>
                                @img class: "tweet_account_avator_tweeter", src: tweeter.profile_image_url

                            @a target: "_blank", href: "https://twitter.com/#{retweeter.screen_name}", =>
                                @img class: "tweet_account_avator_retweeter", src: retweeter.profile_image_url

                    @a class: "tweet_account_names", target: "_blank", href: "https://twitter.com/#{tweeter.screen_name}", =>
                        @strong class: "tweet_account_user-name", tweeter.name
                        @span class: "tweet_account_screen-name", "@#{tweeter.screen_name}"
        else
            fn = (tweeter) ->
                @a class: "tweet_account", target: "_blank", href: "https://twitter.com/#{tweeter.screen_name}", =>
                    if noAvator isnt true then @img(class: "tweet_account_avator", src: tweeter.profile_image_url)
                    @strong class: "tweet_account_user-name", tweeter.name
                    @span class: "tweet_account_screen-name", "@#{tweeter.screen_name}"


        fn.call(viewCtx, tweeter, retweeter)

    _buildQuotedTweet : (viewCtx, tweet) ->
        self = @

        fn = (tweet) ->
            tweeter = tweet.user
            tweetBody = self._processEntities(tweet.text, tweet.entities)

            @div
                class: "tweet tweet--quoted",
                "data-status-id": tweet.id_str
                "data-tweeter-screen-name": tweeter.screen_name
                "data-tweeted-at": tweet.created_at
            , =>
                @div class: "tweet_header", =>
                    self._buildTweetAccountHeader(@, tweeter, null, noAvator: true)
                    @span class: "tweet_times-ago"

                @pre class: "tweet_body", => @raw tweetBody

                @aside class: "tweet_actions", =>
                    @a class: "tweet_actions_item icon icon-link", "data-action": "paste_link"

        fn.call(viewCtx, tweet)

    _buildTweet : (viewCtx, tweet) ->
        formatNumber = do =>
            formatter = Intl.NumberFormat("ja-JP")
            (num) ->
                return "99,999+" if num > 99999
                formatter.format(num)

        self = @

        fn = (tweet) ->
            tweeter = tweet.retweeted_status?.user ? tweet.user
            retweeter = if tweet.retweeted_status? then tweet.user
            tweet = tweet.retweeted_status ? tweet

            tweetBody = self._processEntities(tweet.text, tweet.entities)

            tweetClasses = ["tweet"]
            tweetClasses.push "tweet--reply" if tweet.__.replyToMe

            @li
                class: tweetClasses.join(" "),
                "data-status-id": tweet.id_str
                "data-tweeter-screen-name": tweeter.screen_name
                "data-tweeted-at": tweet.created_at
            , =>
                @div class: "tweet_header", =>
                    self._buildTweetAccountHeader(@, tweeter, retweeter)
                    @span class: "tweet_times-ago"

                @pre class: "tweet_body", => @raw tweetBody

                self._buildExtendedEntities(@, tweet)

                rtClass = if retweeter? then "tweet_actions--hasRetweet" else ""
                @aside class: "tweet_actions #{rtClass}", =>
                    @a class: "tweet_actions_item icon icon-mail-reply", "data-action": "reply"
                    @a class: "tweet_actions_item #{if tweet.favorited then "tweet_actions_item--favorited" else ""} icon icon-star", "data-action": "fav", =>
                        @raw formatNumber(tweet.favorite_count)
                    @a class: "tweet_actions_item #{if tweet.retweeted then "tweet_actions_item--retweeted" else ""} icon icon-git-compare", "data-action": "retweet", =>
                        @raw formatNumber(tweet.retweet_count)
                    @a class: "tweet_actions_item icon icon-link", "data-action": "paste_link"

                    if retweeter?
                        @a class: "tweet_retweeter", =>
                            @text "リツイート: "
                            @img class: "tweet_retweeter_avator", src: retweeter.profile_image_url
                            @strong class: "tweet_retweeter_user-name", retweeter.name

        fn.call(viewCtx, tweet)

    displayTweet : (tweet) ->
        self = @
        el = $$ -> self._buildTweet(@, tweet)
        @insertTimeLineItem el

        return

    insertTimeLineItem : ($el) ->
        $el.prependTo(@tlList).slideUp(0).slideDown(300)

        # Correct old tweets
        childs = @tlList[0].children
        length = childs.length
        loop
            break if length <= 200
            $c = $(childs[--length])
            $c.slideUp 300, -> $c.remove()


    # Helper

    _findElementByStatusId : (statusId) ->
        @tlList.children("li").filter -> @dataset.statusId is statusId


    # Process Twitter stream events

    receiveTweetDeletion : (data) ->
        statusId = data.delete.status.id_str
        $els = @_findElementByStatusId(statusId)
            .addClass("tweet--deleting")
            .slideUp 300, ->
                $els.remove()

    hasBeenFavorite : ({source, target, target_object}) ->
        return if target.id_str isnt @twitter.getUserProfile().id_str

        self = @
        tweet = target_object

        @insertTimeLineItem $$ ->
            @li class: "tweet tweet--notify-fav", =>
                @div class: "icon icon-star", "#{source.name} favorited tweet."
                self._buildTweetAccountHeader(@, tweet.user)
                @pre class: "tweet_body", => @raw tweet.text

        return

    removeFavorited : ({source, target, target_object}) ->
        return if target.id_str isnt @twitter.getUserProfile().id_str

        self = @
        tweet = target_object

        @insertTimeLineItem $$ ->
            @li class: "tweet tweet--notify-unfav", =>
                @div class: "icon icon-star", "#{source.name} cancel favorite."
                self._buildTweetAccountHeader(@, tweet.user)
                @pre class: "tweet_body", => @raw tweet.text

    markFavorite : ({source, target_object}) ->
        return if source.id_str isnt @twitter.getUserProfile().id_str

        el = @_findElementByStatusId(target_object.id_str)
            .find("[data-action='fav']")
            .addClass("tweet_actions_item--favorited")

        return

    unmarkFavorite : ({source, target_object}) ->
        return if source.id_str isnt @twitter.getUserProfile().id_str

        e;@_findElementByStatusId(target_object.id_str)
            .find("[data-action='fav']")
            .removeClass("tweet_actions_item--favorited")
        return


    # ScrollView methods

    getTitle : -> "Twitter Timeline"

    getURI : -> "twitter://"

    destroy: ->
        @disposables.dispose()
        return


    # serialize : ->

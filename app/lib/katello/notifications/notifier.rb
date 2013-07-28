#
# Copyright 2013 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.


# sends notifications, see public instance methods
module Katello
  class Notifications::Notifier
    include Rails.application.routes.url_helpers

    attr_reader :controller, :default_options

    def initialize(controller = nil, options = { })
      @controller      = controller
      @default_options = { :level        => :success,
                           :asynchronous => !controller,
                           :persist      => true,
                           :global       => false,
                           :details      => nil,
                           :request_type => (controller.send :requested_action if controller),
                           :send_as      => 'notices',
                           :user         => nil,
                           :organization => nil }.merge(options)
    end

    # generates error-notice based on invalid record, it's displayed as list, not persisted by default
    # use only for invalid records with data inserted by user, don't use for InvalidRecord exception
    def invalid_record(record, options = { })
      options = { :level   => :error,
                  :send_as => 'validation_errors',
                  :persist => false }.merge options
      notice(record.errors.full_messages.to_a, options)
    end

    # generates success-notice
    def success(message, options = { })
      notice message, options
    end

    # generates message-notice, asynchronous by default
    def message(message, options = { })
      options = { :level => :message, :asynchronous => true }.merge options
      notice message, options
    end

    # generates warning-notice, not persisted by default
    def warning(message, options = { })
      options = { :level => :warning, :persist => false }.merge options
      notice message, options
    end

    # generates error-notice
    def error(message, options = { })
      options = { :level => :error }.merge options
      notice message, options
    end

    # generates error-notice form exception, optionally adding a note
    # @example
    #   exception(an_exception)
    #   exception("some note", an_exception)
    #   exception("some note", an_exception, :asynchronous => true) # options are optional
    def exception(*args)
      options   = args.extract_options!
      exception = args.pop
      note      = args.pop

      case exception
      when ActiveRecord::RecordInvalid
        invalid_record(exception.record, { :persist => true }.merge(options))
      else
        options = { :level   => :error,
                    :details => exception.backtrace.join("\n") }.merge options

        notice [note, "#{exception.message} (#{exception.class.name})",
                (exception.response if exception.respond_to? :response)],
               options
      end
    end

    protected


    # Generate a notice:
    #
    # @param [Array<String>] notices the text to include or Array of texts (nil values are dropped)
    # @param [Hash] options Optional hash containing various optional parameters
    # @option options [Symbol] :level The type of notice to be generated, see {LEVELS}, dafault is `:success`
    # @option options [true, false] :asynchronous
    #   if notifier has controller default is false, if notifier has no controller
    #   (used in model) default is true.
    #   if this notice is associated with an event where
    #   the user would expect to receive a response immediately
    #   as part of a response. This typically applies for events
    #   involving things such as create, update and delete.
    #   IMPORTANT: If creating a synchronous request, the invocation of notice
    #   must be from within a controller (i.e. not a model).
    #
    # @option options [true, false] :persist
    #   default is true, if this notice should be stored via ActiveRecord.
    #   Note: this option only applies when asynchronous is false.
    #
    # @option options [String] :details
    #   String containing additional details. This would typically be to store
    #   information such as a stack trace that is in addition to the notice text.
    #
    # @option options [String] :request_type
    #   String representing the request/action this notice is associated with.  In the case
    #   of notices generated by controllers, this option is not necessary; however,
    #   if the notice is generated by a model, it should be provided.  The typical format
    #   would be something like "controller"+"___"+"action" (e.g. "changesets___promote")
    #
    # @option options [User] :user the user to send the notification to.  If not set, User.current is used
    #
    def notice(notices, options = { })
      options = process_options options
      notices = [*notices].compact
      notices.collect! { |n| n.gsub(/[\<\>]/, '<' => '&lt;', '>' => '&gt;') }

      unless options[:asynchronous]
        # On a sync request, the client should expect to receive a notification
        # immediately without polling. In order to support this, we will send a flash
        # notice.
        if options[:persist]
          notice = persist! notices, true, options

          if controller
            if options[:details]
              link = NoticesController.helpers.link_to('Click here', controller.notices_url)
              notices << _("%s for more details.") % link
            end
            controller.flash[options[:level]] = { options[:send_as] => notices }.to_json
          end
        end
      else
        # On an async request, the client shouldn't expect to receive a notification
        # immediately. As a result, we'll store the notification and it will be
        # retrieved by the client on it's next polling interval.
        persist! notices, false, options
      end
    end

    def persist!(notices, viewed, options)
      Notice.create! :text         => notices.join('<br />'),
                     :details      => options[:details],
                     :level        => options[:level],
                     :global       => options[:global],
                     :request_type => options[:request_type],
                     :organization => options[:organization],
                     :user_notices => [UserNotice.new(:user => options[:user], :viewed => viewed)]
    end

    LEVELS          = [:message, :success, :warning, :error]
    FLAGS           = [true, false]
    SEND_AS_OPTIONS = %w(notices validation_errors)

    def process_options(options)
      options        = default_options.merge options
      options[:user] ||= User.current

      options.assert_valid_keys(*default_options.keys)

      raise ArgumentError, "unknown notice level #{options[:level].inspect}" unless LEVELS.include? options[:level]

      unless SEND_AS_OPTIONS.include? options[:send_as]
        raise ArgumentError, "unknown send as #{options[:send_as].inspect}"
      end

      [:asynchronous, :persist, :global].each do |flag|
        raise ArgumentError,
              "#{flag} has to be true || false, but is #{options[flag].inspect}" unless FLAGS.include? options[flag]
      end

      raise ArgumentError, "cannot be asynchronous without persist" if options[:asynchronous] && !options[:persist]
      raise ArgumentError, "cannot use details without persist" if options[:details] && !options[:persist]

      return options
    end
  end
end

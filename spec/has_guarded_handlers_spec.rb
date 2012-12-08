require 'spec_helper'

describe HasGuardedHandlers do
  subject do
    Object.new.tap do |o|
      o.extend HasGuardedHandlers
    end
  end

  let(:event) { mock 'Event' }
  let(:response) { mock 'Response' }

  it 'can register a handler' do
    response.expects(:call).twice.with(event)
    subject.register_handler(:event) { |e| response.call e }
    subject.trigger_handler(:event, event).should be_true
    subject.trigger_handler(:event, event).should be_true
  end

  it 'can register a handler for all events, regardless of category' do
    response.expects(:call).twice.with(event)
    subject.register_handler { |e| response.call e }
    subject.trigger_handler :event, event
    subject.trigger_handler :bah, event
  end

  it 'can register a one-shot (tmp) handler' do
    response.expects(:call).once.with(event)
    event.expects(:foo).once.returns :bar

    nomatch_event = mock 'Event(nomatch)'
    nomatch_event.expects(:foo).once.returns :baz

    subject.register_tmp_handler(:event, :foo => :bar) { |e| response.call e }

    subject.trigger_handler :event, nomatch_event
    subject.trigger_handler :event, event
  end

  it 'can unregister a handler after registration' do
    response.expects(:call).once.with(event)
    subject.register_handler(:event) { |e| response.call e }
    id = subject.register_handler(:event) { |e| response.call :foo }
    subject.unregister_handler :event, id
    subject.trigger_handler :event, event
  end

  it 'does not fail when no handlers are set' do
    lambda do
      subject.trigger_handler :event, event
    end.should_not raise_error
    subject.trigger_handler(:event, event).should be_false
  end

  it 'allows for breaking out of handlers' do
    response.expects(:handle).once
    response.expects(:fail).never
    subject.register_handler :event do |_|
      response.handle
      throw :halt
      response.fail
    end
    subject.trigger_handler :event, event
  end

  it 'allows for passing to the next handler of the same type' do
    response.expects(:handle1).once
    response.expects(:handle2).once
    response.expects(:fail).never
    subject.register_handler :event do |_|
      response.handle1
      throw :pass
      response.fail
    end
    subject.register_handler :event do |_|
      response.handle2
    end
    subject.trigger_handler :event, event
  end

  describe 'when registering handlers with the same priority' do
    it 'preserves the order of specification of the handlers' do
      sequence = sequence 'handler_priority'
      response.expects(:handle1).once.in_sequence sequence
      response.expects(:handle2).once.in_sequence sequence
      response.expects(:handle3).once.in_sequence sequence
      subject.register_handler :event do |_|
        response.handle1
        throw :pass
      end
      subject.register_handler :event do |_|
        response.handle2
        throw :pass
      end
      subject.register_handler :event do |_|
        response.handle3
        throw :pass
      end
      subject.trigger_handler :event, event
    end
  end

  describe 'when registering handlers with a specified priority' do
    it 'executes handlers in that order' do
      sequence = sequence 'handler_priority'
      response.expects(:handle1).once.in_sequence sequence
      response.expects(:handle2).once.in_sequence sequence
      response.expects(:handle3).once.in_sequence sequence
      subject.register_handler_with_priority :event, -10 do |_|
        response.handle3
        throw :pass
      end
      subject.register_handler_with_priority :event, 0 do |_|
        response.handle2
        throw :pass
      end
      subject.register_handler_with_priority :event, 10 do |_|
        response.handle1
        throw :pass
      end
      subject.trigger_handler :event, event
    end
  end

  it 'can clear handlers' do
    response.expects(:call).once

    subject.register_handler(:event) { |_| response.call }
    subject.trigger_handler :event, event

    subject.clear_handlers :event
    subject.trigger_handler :event, event
  end

  describe 'guards' do
    GuardMixin = Module.new
    class GuardedObject
      include GuardMixin
    end

    it 'can be a class' do
      response.expects(:call).once
      subject.register_handler(:event, GuardedObject) { |_| response.call }

      subject.trigger_handler :event, GuardedObject.new
      subject.trigger_handler :event, Object.new
    end

    it 'can be a module' do
      response.expects(:call).once
      subject.register_handler(:event, GuardMixin) { |_| response.call }

      subject.trigger_handler :event, GuardedObject.new
      subject.trigger_handler :event, Object.new
    end

    it 'can be a symbol' do
      response.expects(:call).once
      subject.register_handler(:event, :chat?) { |_| response.call }

      event.expects(:chat?).returns true
      subject.trigger_handler :event, event

      event.expects(:chat?).returns false
      subject.trigger_handler :event, event
    end

    it 'can be a hash with string match' do
      response.expects(:call).once
      subject.register_handler(:event, :body => 'exit') { |_| response.call }

      event.expects(:body).returns 'exit'
      subject.trigger_handler :event, event

      event.expects(:body).returns 'not-exit'
      subject.trigger_handler :event, event
    end

    it 'can be a hash with a value' do
      response.expects(:call).once
      subject.register_handler(:event, :number => 0) { |_| response.call }

      event.expects(:number).returns 0
      subject.trigger_handler :event, event

      event.expects(:number).returns 1
      subject.trigger_handler :event, event
    end

    it 'can be a hash with a regexp' do
      response.expects(:call).once
      subject.register_handler(:event, :body => /exit/) { |_| response.call }

      event.expects(:body).returns 'more than just exit, but exit still'
      subject.trigger_handler :event, event

      event.expects(:body).returns 'keyword not found'
      subject.trigger_handler :event, event

      event.expects(:body).returns nil
      subject.trigger_handler :event, event
    end

    it 'can be a hash with arguments' do
      response.expects(:call).once
      subject.register_handler(:event, [:[], :foo] => :bar) { |_| response.call }

      subject.trigger_handler :event, {:foo => :bar}
      subject.trigger_handler :event, {:foo => :baz}
      subject.trigger_handler :event, {}
    end

    it 'can be a hash with an array' do
      response.expects(:call).twice
      subject.register_handler(:event, :type => [:result, :error]) { |_| response.call }

      event = mock 'Event'
      event.expects(:type).at_least_once.returns :result
      subject.trigger_handler :event, event

      event = mock 'Event'
      event.expects(:type).at_least_once.returns :error
      subject.trigger_handler :event, event

      event = mock 'Event'
      event.expects(:type).at_least_once.returns :get
      subject.trigger_handler :event, event
    end

    it 'chained are treated like andand (short circuited)' do
      response.expects(:call).once
      subject.register_handler(:event, :type => :get, :body => 'test') { |_| response.call }

      event = mock 'Event'
      event.expects(:type).at_least_once.returns :get
      event.expects(:body).returns 'test'
      subject.trigger_handler :event, event

      event = mock 'Event'
      event.expects(:type).at_least_once.returns :set
      event.expects(:body).never
      subject.trigger_handler :event, event
    end

    it 'within an Array are treated as oror (short circuited)' do
      response.expects(:call).twice
      subject.register_handler(:event, [{:type => :get}, {:body => 'test'}]) { |_| response.call }

      event = mock 'Event'
      event.expects(:type).at_least_once.returns :set
      event.expects(:body).returns 'test'
      subject.trigger_handler :event, event

      event = mock 'Event'
      event.stubs(:type).at_least_once.returns :get
      event.expects(:body).never
      subject.trigger_handler :event, event
    end

    it 'can be a lambda' do
      response.expects(:call).once
      subject.register_handler(:event, lambda { |e| e.number % 3 == 0 }) { |_| response.call }

      event.expects(:number).at_least_once.returns 3
      subject.trigger_handler :event, event

      event.expects(:number).at_least_once.returns 2
      subject.trigger_handler :event, event
    end

    it 'raises an error when a bad guard is tried' do
      lambda {
        subject.register_handler(:event, 0) {}
      }.should raise_error RuntimeError
    end
  end
end

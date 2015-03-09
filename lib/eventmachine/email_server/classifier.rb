require 'eventmachine'
require 'classifier'
require 'madeleine'

module EventMachine
  module EmailServer
    class Classifier
      def initialize(datafile, categories, blocked_categories)
        @categories = categories || [:good, :bad]
        @blocked_categories = blocked_categories || [:bad]
        @categories.map! { |c| c.prepare_category_name.to_s }
        @blocked_categories.map! { |c| c.prepare_category_name.to_s }
        @madeleine = SnapshotMadeleine.new(datafile) {
            ::Classifier::Bayes.new(*categories)
        }
        @classifier = @madeleine.system
      end
      
      def train(category, email)
        @classifier.train(category, email)
        @madeleine.take_snapshot
      end
      
      def classify(email)
        @classifier.classify(email)
      end
      
      def block?(email)
        c = classify(email)
        if @blocked_categories.index(c).nil?
          return false
        end
        true
      end
    end
  end
end
    
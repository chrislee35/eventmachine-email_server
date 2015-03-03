require_relative 'base'

module EventMachine
  module EmailServer
    class MemoryUserStore < AbstractUserStore
      def initialize
        @users = Array.new
      end
      
      def add_user(user)
        @users << user
      end
      
      def delete_user(user)
        @users -= [user]
      end

      def user_by_username(username)
        @users.find {|user| user.username == username}
      end
      
      def user_by_emailaddress(address)
        @users.find {|user| user.address == address}
      end
      
      def user_by_id(id)
        @users.find {|user| user.id == id}
      end
    end
    
    class MemoryEmailStore < AbstractEmailStore
      def initialize
        @emails = Array.new
      end
      
      def emails_by_userid(uid)
        @emails.find_all {|email| email.uid == uid}
      end
      
      def save_email(email)
        @emails << email
      end
      
      def delete_email(email)
        @emails -= [email]
      end
      
      def delete_id(id)
        @emails.delete_if {|email| email.id == id}
      end
      
      def delete_user(uid)
        @emails.delete_if {|email| email.uid == uid}
      end
      
      def count
        @emails.length
      end
    end
  end
end
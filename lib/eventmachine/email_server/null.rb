require_relative 'base'

module EventMachine
  module EmailServer
    class NullUserStore < AbstractUserStore
      def initialize
        @user = User.new(1,"null","null","null")
      end
      
      def add_user(user)
      end
      
      def delete_user(user)
      end

      def user_by_username(username)
        u = @user.clone
        u.userame = username
        u
      end
      
      def user_by_emailaddress(address)
        u = @user.clone
        u.address = address
        u
      end
      
      def user_by_id(id)
        u = @user.clone
        u.id = id
        u
      end
    end
    
    class NullEmailStore < AbstractEmailStore
      def initialize
      end
      
      def emails_by_userid(uid)
        []
      end
      
      def save_email(email)
      end
      
      def delete_email(email)
      end
      
      def delete_id(id)
      end
      
      def delete_user(uid)
      end
    end
  end
end
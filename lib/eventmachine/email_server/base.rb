module EventMachine
  module EmailServer
    class User < Struct.new(:id,:username,:password,:address); end
    class Email < Struct.new(:id,:from,:to,:subject,:body,:uid,:marked); end
    
    class AbstractUserStore
      def add_user(user)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def <<(user)
        add_user(user)
      end

      def delete_user(user)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def -(user)
        delete_user(user)
      end

      def user_by_username(username)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def user_by_emailaddress(email)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
    end
        
    class AbstractEmailStore
      def emails_by_userid(id)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def save_email(email)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def <<(email)
        save_email(email)
      end
      
      def delete_email(email)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def -(email)
        delete_email(email)
      end

      def delete_id(id)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def delete_user(uid)
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
      
      def count
        raise "Unimplemented, please use a subclass of #{self.class}"
      end
    end
  end
end
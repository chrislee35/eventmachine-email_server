require_relative 'base'
require 'sqlite3'

module EventMachine
  module EmailServer
    class Sqlite3UserStore < AbstractUserStore
      def initialize(sqlite3, tablename = "users")
        @class = User
        @fields = @class.members.map {|x| x.to_s}.join(", ")
        @tablename = tablename
        if sqlite3.class == SQLite3::Database
          @db = sqlite3
        else
          @db = SQLite3::Database.new(sqlite3)
        end
        if @db.table_info(tablename).length == 0
          @db.execute("CREATE TABLE #{@tablename} (#{@fields})")
        end
      end
      
      def add_user(user)
        if user.id
          u = user_by_id(user.id)
        end
        if u
          @db.execute("UPDATE #{@tablename} SET username=?, password=?, address=? WHERE id=?", 
            user.username,
            user.password,
            user.address,
            user.id)
        else
          @db.execute("INSERT INTO #{@tablename} (id,username,password,address) VALUES (?,?,?,?)", 
            user.id,
            user.username,
            user.password,
            user.address)
        end
      end
      
      def delete_user(user)
        if user.id
          @db.execute("DELETE FROM #{@tablename} WHERE id = ?", user.id)
        end
      end

      def user_by_field(field, value)
    		rs = @db.execute("SELECT #{@fields} FROM #{@tablename} WHERE #{field}='#{value}'")
    		return nil unless rs
    		rs.each do |row|
    			return User.new(*row)
    		end
        return nil
      end
        
      def user_by_username(username)
        user_by_field("username", username)
      end
      
      def user_by_emailaddress(address)
        user_by_field("address", address)
      end
      
      def user_by_id(id)
        user_by_field("id", id)
      end
    end
    
    class Sqlite3EmailStore < AbstractEmailStore
      def initialize(sqlite3, tablename = "emails")
        @class = Email
        @fields = "'"+@class.members.map {|x| x.to_s}.join("', '")+"'"
        @tablename = tablename
        if sqlite3.class == SQLite3::Database
          @db = sqlite3
        else
          @db = SQLite3::Database.new(sqlite3)
        end
        if @db.table_info(tablename).length == 0
          fields = @fields.gsub(/'id'/, 'id integer primary key autoincrement')
          @db.execute("CREATE TABLE #{@tablename} (#{fields})")
        end
      end
      
      def emails_by_field(field, value)
    		rs = @db.execute("SELECT #{@fields} FROM #{@tablename} WHERE ?=?", field, value)
    		return nil unless rs
        emails = Array.new
    		rs.each do |row|
    			emails << Email.new(*row)
    		end
        emails
      end
      
      def emails_by_userid(uid)
        emails_by_field("uid", uid)
      end
      
      def quote( string )
        string.gsub( /'/, "''" )
      end
      private :quote
      
      def save_email(email)
        if email.id
          # I'm being too crafty here.. this is bad style
          args = (@class.members - [:id]).map{|f| email.send(f)}
          args << email.send(:id)
          @db.execute("UPDATE #{@tablename} SET " +
            (@class.members - [:id]).map { |field| "#{field} = ?"}.join(", ") +
            " WHERE id = ?", *args)
        else
          email.id = "NULL"
          args = (@class.members).map{|f| email.send(f)}
          qs = args.map{|x| "'#{quote(x.to_s)}'"}.join(",").gsub(/'NULL'/, "NULL")
          @db.execute("INSERT INTO #{@tablename} (#{@fields}) VALUES (#{qs})")
          rs = @db.execute("SELECT last_insert_rowid()")
          rs.each do |row|
            email.id = *row
          end
        end
        email.id
      end
      
      def delete_email(email)
        if email.id
          @db.execute("DROP FROM #{@tablename} WHERE id = ?", email.id)
        end
      end
      
      def delete_by_field(field, value)
        @db.execute("DROP FROM #{@tablename} WHERE #{field} = ?", value)
      end
      
      def delete_id(id)
        delete_by_field("id", id)
      end
      
      def delete_user(uid)
        delete_by_field("uid", uid)
      end
    end
  end
end
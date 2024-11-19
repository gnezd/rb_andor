require 'pry'
class Abc
    puts "hey Abc initialized"
    @name = name
  class Def
    def initialize(name)
      puts "Def initialized"
    end
  end
  def make_Def
    @def = Def.new('zzz')
    puts "Made a Def object in #{@name}"
  end
  def check_Def
    puts defined?(@def) ? 'Yes!' : 'No...'
  end
  def def_newclass
    cmd = <<-EOCM
      class NewClass
        def initialize
          puts "NewClass made!"
        end
      end
    EOCM
    eval cmd
  end
end

abc1 = Abc.new
abc1.make_Def
abc1.check_Def
binding.pry
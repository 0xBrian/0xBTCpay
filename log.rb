module Log
  def log(*args)
    tag = [@name, @id].compact * " "
    STDOUT.print Time.now.strftime("[#{tag}] %Y-%m-%d %H:%M:%S.%6N ")
    STDOUT.puts *args
  end
end

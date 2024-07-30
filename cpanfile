use File::HomeDir;
my $home = File::HomeDir->my_home;


requires 'Config::YAML';
requires 'DateTime';
requires 'File::HomeDir';
requires 'HTTP::Request';
requires 'HTTP::Request::Common';
requires 'HTTP::Thin';
requires 'JSON';
requires 'Module::Runtime';
requires 'Moo';
requires 'MooX::Singleton';
requires 'MooX::HandlesVia';
requires 'Sys::Hostname::Long';
requires 'Try::Tiny';
requires 'Types::Standard';
requires 'AnyEvent';
requires 'AnyEvent::Fork'; 
requires 'AnyEvent::Fork::Pool';
requires 'String::CamelCase';
requires 'common::sense';
requires 'Proc::Daemon';
requires 'Mo::default';
requires 'Sys::OsRelease';
requires 'Text::ParseWords';
requires 'Text::Template::Simple';


requires 'RaffiWare::APIUtils', '>= 0.01',
  dist   => 'RAFFIWARE/RaffiWare-APIUtils-0.01.tar.gz',
  mirror => "file://$home/darkpan/"; 

on 'test' => sub {
  requires 'Test::Deep';
  requires 'Text::Diff'; 
};

on 'build' => sub {
   requires 'App::FatPacker';
   requires 'Sys::GNU::ldconfig';
   requires 'PAR::Packer';
   requires 'local::lib';
}


# 
# on 'develop' => sub {
#   recommends 'Devel::NYTProf';
# };

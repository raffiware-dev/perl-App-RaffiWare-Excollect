use File::HomeDir;
my $home = File::HomeDir->my_home;

use Cwd;
my $cwd = getcwd;


requires 'Config::YAML';
requires 'Config::JSON'; 
requires 'DateTime';
requires 'File::HomeDir';
requires 'HTTP::Request';
requires 'HTTP::Request::Common';
requires 'HTTP::Thin';
requires 'JSON';
requires 'JSON::XS';
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
requires 'IO::Socket::SSL';
requires 'Crypt::Random';
requires 'Specio', '>= 0.50';
requires 'AnyEvent::WebSocket::Client';
requires 'Scalar::Util';
requires 'IO::Stty';
requires 'IO::Tty';
requires 'Unicode::Escape';
requires 'IO::Tty::Util';
requires 'LWP::Protocol::https';
requires 'Crypt::RFC8188';

requires 'RaffiWare::APIUtils', '>= 0.001',
  dist   => 'RAFFIWARE/RaffiWare-APIUtils-0.002003.tar.gz',
  mirror => "file://$home/darkpan/",
  url    => "file://$cwd/RaffiWare-APIUtils-0.002003.tar.gz"; 

on 'test' => sub {
  requires 'Test::Most';
  requires 'Test::Deep';
  requires 'Text::Diff'; 
};

on 'build' => sub {
   requires 'App::FatPacker';
   requires 'Sys::GNU::ldconfig';
   requires 'PAR::Packer';
   requires 'local::lib';
   requires 'Perl::Strip';
}


# 
# on 'develop' => sub {
#   recommends 'Devel::NYTProf';
# };

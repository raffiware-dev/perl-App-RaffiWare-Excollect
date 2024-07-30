#!/user/bin/env perl

# For fatpack trace
use lib 'local';
use lib 'lib';

use Mo;
use Data::Perl::Collection::Array::MooseLike;
use Data::Perl::Collection::Hash::MooseLike;
use Data::Perl::String::MooseLike;
use Data::Perl::Bool::MooseLike;
use Data::Perl::Number::MooseLike;
use Data::Perl::Code;

use Text::Template::Simple::Base::Compiler;
use Text::Template::Simple::Base::Examine;
use Text::Template::Simple::Base::Include;
use Text::Template::Simple::Base::Parser;

use App::RaffiWare::Role::HasLogger;
use App::RaffiWare::Role::TakesCmdArgs;
use App::RaffiWare::Role::IsCmd;
use App::RaffiWare::Role::DoesLogging;
use App::RaffiWare::Role::HasCfg;
use App::RaffiWare::Role::HasAPIClient;
use App::RaffiWare::Cfg;
use App::RaffiWare::ExCollect;
use App::RaffiWare::ExCollect::Worker;
use App::RaffiWare::ExCollect::Role::HasJobs;
use App::RaffiWare::ExCollect::Job;
use App::RaffiWare::ExCollect::Job::Logger;
use App::RaffiWare::ExCollect::Job;
use App::RaffiWare::ExCollect::API;
use App::RaffiWare::ExCollect::Cmd;
use App::RaffiWare::ExCollect::Cmd;
use App::RaffiWare::ExCollect::Cmd::Watcher;
use App::RaffiWare::ExCollect::Cmd::ClientInit;
use App::RaffiWare::ExCollect::Cmd::Job;
use App::RaffiWare::Logger;
use App::RaffiWare::API; 
use App::RaffiWare::ExCollect::HostData; 

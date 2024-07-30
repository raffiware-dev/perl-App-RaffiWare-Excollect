use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'App::RaffiWare::ExCollect',
    VERSION_FROM      => 'lib/App/RaffiWare/ExCollect.pm', 
    "EXE_FILES" => [
      "bin/exc",
      "bin/anyevent-fork"
    ],
    PREREQ_PM         => {
    },
    ABSTRACT          => 'API client for ExCollect', 
    AUTHOR            => 'RaffiWare <dev@raffiware.io>',
    LICENSE           => 'mit',

);

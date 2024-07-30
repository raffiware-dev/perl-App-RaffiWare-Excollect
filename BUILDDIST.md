# Building the CPAN Distribution

Make sure the distribution for RaffiWare::APIUtils is copied into the root of this repository.

```
   cpanm OrePAN2
   orepan2-inject --author=RaffiWare  RaffiWare-APIUtils-0.01.tar.gz ~/darkpan/
   orepan2-indexer ~/darkpan/
   cpanm --installdeps --with-develop .
   ./maint/build_fatlib.pl
   ./maint/build.pl 
``` 

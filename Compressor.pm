package CSS::Compressor;

use strict;
use warnings;

use Exporter qw( import );

our @EXPORT_OK = qw( compress );

our $VERSION = '0.01';

our $MARKER;

BEGIN {
    $MARKER = uc __PACKAGE__;
    $MARKER =~ tr!:!_!s;
}

my (
    $RE_BACKGROUND_POSITION,
    $RE_TRANSFORM_ORIGIN_MOZ,
    $RE_TRANSFORM_ORIGIN_MS,
    $RE_TRANSFORM_ORIGIN_O,
    $RE_TRANSFORM_ORIGIN_WEBKIT,
    $RE_TRANSFORM_ORIGIN,
    $RE_BORDER,
    $RE_BORDER_TOP,
    $RE_BORDER_RIGHT,
    $RE_BORDER_BOTTOM,
    $RE_BORDER_LEFT,
    $RE_OUTLINE,
    $RE_BACKGROUND,
) = map +(
    join '' => map m![a-z]!
       ? '['.ucfirst($_.$_).']'
       : '\\'.$_,
       split m//
) => qw(
    background-position
       moz-transform-origin
        ms-transform-origin
         o-transform-origin
    webkit-transform-origin
           transform-origin
    border
    border-top
    border-right
    border-bottom
    border-right
    outline
    background
);

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  compress
#
#  IN: 1 uncompressed CSS
# OUT: 1 compressed CSS

sub compress {
    my ( $css ) = @_;
    my @comments,
    my @tokens;

    # collect all comment blocks...
    $css =~ s! /\* (.*?) \*/
             ! '/*___'.$MARKER.'_PRESERVE_CANDIDATE_COMMENT_'.
               ( -1 + push @comments => $1 ).'___*/'
             !sogex;

    # preserve strings so their content doesn't get accidentally minified
    $css =~ s! " ( [^"\\]*(?:\\.[^"\\]*)* ) " !
        $_ = $1,

        # maybe the string contains a comment-like substring?
        # one, maybe more? put'em back then
        s/___${MARKER}_PRESERVE_CANDIDATE_COMMENT_([0-9]+)___/$comments[$1]/go,

        # minify alpha opacity in filter strings
        s/progid:DXImageTransform\.Microsoft\.Alpha\(Opacity=/alpha(opacity=/gi,

        '"___'.$MARKER.'_PRESERVED_TOKEN_'.(-1+push @tokens => $_).'___"'
       !sgxe;
    $css =~ s! ' ( [^'\\]*(?:\\.[^'\\]*)* ) ' !
        $_ = $1,

        s/___${MARKER}_PRESERVE_CANDIDATE_COMMENT_([0-9]+)___/$comments[$1]/go,

        s/progid:DXImageTransform\.Microsoft\.Alpha\(Opacity=/alpha(opacity=/gi,

        '\'___'.$MARKER.'_PRESERVED_TOKEN_'.(-1+push @tokens => $_).'___\''
       !sgxe;

    # strings are safe, now wrestle the comments

    # ! in the first position of the comment means preserve
    # so push to the preserved tokens while stripping the !
    0 == index $_->[1] => '!'
      and
        $css =~ s!___${MARKER}_PRESERVE_CANDIDATE_COMMENT_$_->[0]___!
                 '___'.$MARKER.'_PRESERVED_TOKEN_'.(-1+push @tokens => $_->[1]).'___'!e

    # keep empty comments after child selectors (IE7 hack)
    # e.g. html >/**/ body
    or 0 == length $_->[1]
      and
        $css =~ s!>/\*___${MARKER}_PRESERVE_CANDIDATE_COMMENT_$_->[0]___!
                 '>/*___'.$MARKER.'_PRESERVED_TOKEN_'.(-1+push @tokens => '').'___'!e

    # \ in the last position looks like hack for Mac/IE5
    # shorten that to /*\*/ and the next one to /**/
    or '\\' eq substr $_->[1] => -1
      and
        $css =~ s!___${MARKER}_PRESERVE_CANDIDATE_COMMENT_$_->[0]___!
                 '___'.$MARKER.'_PRESERVED_TOKEN_'.(-1+push @tokens => '\\').'___'!e &&
            # attention: inline modification
            ++$_->[0] &&
        $css =~ s!___${MARKER}_PRESERVE_CANDIDATE_COMMENT_$_->[0]___!
                 '___'.$MARKER.'_PRESERVED_TOKEN_'.(-1+push @tokens => '').'___'!e

        for map +[ $_, $comments[$_] ], 0..$#comments;

    # in all other cases kill the comment
    $css =~ s!/\*___${MARKER}_PRESERVE_CANDIDATE_COMMENT_([0-9]+)___\*/!!g;

    # Normalize all whitespace strings to single spaces. Easier to work with that way.
    $css =~ s!\s+! !g;


    # From here on all white space is just space - no more multi line matches!


    # Remove the spaces before the things that should not have spaces before them.
    # But, be careful not to turn "p :link {...}" into "p:link{...}"
    # Swap out any pseudo-class colons with the token, and then swap back.
    $css =~ s! ( \} [^{:]+ (?:: [^{:]+)+ \{ ) !
              $_ = $1,
              s/:/___${MARKER}_PSEUDOCLASSCOLON___/go,
              s/\\([\\\$])/\\$1/g,
              $_
             !gxe;
    $css =~ s! ( ^  [^{:]+ (?:: [^{:]+)+ \{ ) !
              $_ = $1,
              s/:/___${MARKER}_PSEUDOCLASSCOLON___/go,
              s/\\([\\\$])/\\$1/g,
              $_
             !xe;

    # Remove spaces before the things that should not have spaces before them.
    $css =~ s/ +([!{};:>+()\],])/$1/g;

    # bring back the colon
    $css =~ s!___${MARKER}_PSEUDOCLASSCOLON___!:!go;

    # retain space for special IE6 cases
    $css =~ s!:first\-(line|letter)([{,])!:first-$1 $2!g;

    # no space after the end of a preserved comment
    $css =~ s!\*/ !*/!g;

    # If there is a @charset, then only allow one, and push to the top of the file.
    $css =~ s!^(.*)(\@charset "[^"]*";)!$2$1!g;
    $css =~ s!^( *\@charset [^;]+; *)+!$1!g;

    # Put the space back in some cases, to support stuff like
    # @media screen and (-webkit-min-device-pixel-ratio:0){
    $css =~ s! \b and \( !and (!gx;

    # Remove the spaces after the things that should not have spaces after them.
    $css =~ s/([!{},;:>+(\[]) +/$1/g;

    # Replace 0.6 to .6, but only when preceded by :
    $css =~ s!:0+\.([0-9]+)!:.$1!g;

    # remove unnecessary semicolons
    $css =~ s!;+\}!}!g;

    # Replace 0(px,em,%) with 0
    $css =~ s!([ :]0)(?:px|em|%|in|cm|mm|pc|pt|ex)!$1!g;

    # Replace 0 0 0 0; with 0.
    $css =~ s!:0(?: 0){0,3}(;|})!:0$1!g;

    # Replace background-position:0; with background-position:0 0;
    # same for transform-origin
    $css =~ s! $RE_BACKGROUND_POSITION     :0 ( [;}] ) !background-position:0 0$1!gox;
    $css =~ s! $RE_TRANSFORM_ORIGIN_MOZ    :0 ( [;}] ) !moz-transform-origin:0 0$1!gox;
    $css =~ s! $RE_TRANSFORM_ORIGIN_MS     :0 ( [;}] ) !ms-transform-origin:0 0$1!gox;
    $css =~ s! $RE_TRANSFORM_ORIGIN_O      :0 ( [;}] ) !o-transform-origin:0 0$1!gox;
    $css =~ s! $RE_TRANSFORM_ORIGIN_WEBKIT :0 ( [;}] ) !webkit-transform-origin:0 0$1!gox;
    $css =~ s! $RE_TRANSFORM_ORIGIN        :0 ( [;}] ) !transform-origin:0 0$1!gox;

    # Replace 0.6 to .6, but only when preceded by : or a white-space
    $css =~ s! 0+\.([0-9]+)! .$1!g;

    # Shorten colors from rgb(51,102,153) to #336699
    # This makes it more likely that it'll get further compressed in the next step.
    $css =~ s!rgb *\( *([0-9, ]+) *\)!
               sprintf('#%02x%02x%02x',
                 split(m/ *, */, $1, 3) )
             !ge;

    # Shorten colors from #AABBCC to #ABC. Note that we want to make sure
    # the color is not preceded by either ", " or =. Indeed, the property
    #     filter: chroma(color="#FFFFFF");
    # would become
    #     filter: chroma(color="#FFF");
    # which makes the filter break in IE.
    $css =~ s!
        ([^"'= ][ ]*)
        \#
        ([0-9a-fA-F]) # a
        ([0-9a-fA-F]) # a
        ([0-9a-fA-F]) # b
        ([0-9a-fA-F]) # b
        ([0-9a-fA-F]) # c
        ([0-9a-fA-F]) # c
      !
        #$1.'#'.lc
        #  ( lc $2.$4.$6 eq lc $3.$5.$7
        #     ? $2.$4.$6
        #     : $2.$3.$4.$5.$6.$7 )
        # XXX: this is quite stupid and what I consider a bug but at the moment
        #      we more care about compatibility
        lc
           ( lc $2.$4.$6 eq lc $3.$5.$7
              ? $1.'#'.$2.$4.$6
              : $1.'#'.$2.$3.$4.$5.$6.$7 )
      !gex;

    # border: none -> border:0
    $css =~ s!$RE_BORDER:none([;}])!border:0$1!gox;
    $css =~ s!$RE_BORDER_TOP:none([;}])!border-top:0$1!gox;
    $css =~ s!$RE_BORDER_RIGHT:none([;}])!border-right:0$1!gox;
    $css =~ s!$RE_BORDER_BOTTOM:none([;}])!border-bottom:0$1!gox;
    $css =~ s!$RE_BORDER_LEFT:none([;}])!border-right:0$1!gox;  # XXX: bug/typo in yuicompressor
    $css =~ s!$RE_OUTLINE:none([;}])!outline:0$1!gox;
    $css =~ s!$RE_BACKGROUND:none([;}])!background:0$1!gox;

    # shorter opacity IE filter
    $css =~ s!progid:DXImageTransform\.Microsoft\.Alpha\(Opacity=!alpha(opacity=!gi;

    # Remove empty rules.
    $css =~ s![^{}/;]+\{\}!!g;

    # Replace multiple semi-colons in a row by a single one
    # See SF bug #1980989
    $css =~ s!;;+!;!g;

    # restore preserved comments and strings
    $css =~ s!___${MARKER}_PRESERVED_TOKEN_([0-9]+)___!$tokens[$1]!go;

    # Trim the final string (for any leading or trailing white spaces)
    $css =~ s!\A +!!;
    $css =~ s! +\z!!;

    $css;
}

1;

__END__

=head1 NAME

CSS::Compressor - Perl extension for CSS minification

=head1 SYNOPSIS

  use CSS::Compressor qw( reduce );
  blah blah blah

=head1 DESCRIPTION

Stub documentation for CSS::Compressor, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.

=head1 SEE ALSO

L<http://developer.yahoo.com/yui/compressor/>

L<https://github.com/yui/yuicompressor>

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Simon Bertrang, E<lt>simon@ams7.corp.booking.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Simon Bertrang

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.3 or,
at your option, any later version of Perl 5 you may have available.

=cut

# vim: ts=4 sw=4 et:

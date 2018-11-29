
use Test::More
    tests => 2;

BEGIN {
    use_ok('CSS::Compressor' => qw( css_compress ) );
}

my $result = css_compress(<<CSS);
@supports ( (display: flex)  or  (display: -webkit-flex) ) {
    .grid {
        display: flex;
    }
}
CSS

is $result => '@supports((display:flex) or (display:-webkit-flex)){.grid{display:flex}}' => 'match';


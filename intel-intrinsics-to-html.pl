#! /usr/bin/env perl

use strict;
use warnings;
use XML::Parser;
use File::Copy;
use File::Path qw(make_path remove_tree);
use utf8;

my @stack;
my $result;

our $outdir = 'IntelIntrinsics.docset';

remove_tree $outdir if -e $outdir;

sub on_start {
  my ($expat, $elem, %attrs) = @_;

  my $d = { Name => $elem, Attrs => \%attrs };

  if (scalar @stack) {
    push @{$stack[-1]->{Children}}, $d;
  }

  push @stack, $d;
}

sub on_end {
  if (scalar @stack == 1) {
    $result = $stack[0];
  }
  pop @stack;
}

sub on_char {
  my ($expat, $str) = @_;
  $stack[-1]->{Text} .= $str;
}

my $p = XML::Parser->new(Handlers => {
  Start => \&on_start,
  End => \&on_end,
  Char => \&on_char,
});

print "Parsing $ARGV[0]\n";
$p->parsefile($ARGV[0]);

sub get_child {
  my ($n, $name, $default) = @_;
  for my $child (@{$n->{Children}}) {
    if ($child->{Name} eq $name) {
      return $child;
    }
  }
  return $default;
}

sub get_children {
  my ($n, $name) = @_;
  my @result;
  for my $child (@{$n->{Children}}) {
    if ($child->{Name} eq $name) {
      push @result, $child;
    }
  }
  return @result;
}

my $by_tech = {};

for my $insn (@{$result->{Children}}) {
  my $tech = $insn->{Attrs}->{tech} || "Other";
  push @{$by_tech->{$tech}}, $insn;
}

make_path "$outdir/Contents/Resources/Documents" or die "couldn't make dir: $!";

print "Generating HTML\n";
# Generate HTML
open my $index, ">", "$outdir/Contents/Resources/Documents/index.html" or die "$!";
print $index <<END;
<html>
<head><title>Intel Intrinsics</title></head>
<link rel='stylesheet' type='text/css' href='ssestyle.css'>
<body>
<div class='section'>About Intel Intrinsics</div>

<p> This docset was built from data downloaded from the <a
href="https://software.intel.com/sites/landingpage/IntrinsicsGuide/">Intel
Intrinsics Guide</a>.

<div class='section'>Technology Index</div>
<ul>
END

sub get_category {
  my $insn = shift;
  if (my $category = get_child $insn, 'category') {
    return $category->{Text};
  }
  return "Other";
}

for my $k (sort keys %$by_tech) {
  my $v = $by_tech->{$k};
  my $tech_id = $k;
  $tech_id =~ tr/A-Za-z0-9/_/c;

  print $index "<li><a href='$tech_id.html'>$k</a></li>\n";

  open my $techf, '>', "$outdir/Contents/Resources/Documents/$tech_id.html" or die "open $!";

  print $techf <<END;
<html>
<head><title>$k Intrinsics</title></head>
<link rel='stylesheet' type='text/css' href='ssestyle.css'>
<body>
<div class='section'>$k Intrinsics</div>
END

  my $prev_category = '';
  foreach my $insn (sort { get_category($a) cmp get_category($b) || $a->{Attrs}->{name} cmp $b->{Attrs}->{name}} @$v) {
    my $odir = "$outdir/Contents/Resources/Documents/$tech_id";
    unless (-e $odir) { 
      make_path $odir or die "couldn't make $odir: $!";
    }
    my $fn = "$odir/$insn->{Attrs}->{name}.html";

    # Print technology index entry
    my $category = get_category $insn;
    if ($prev_category ne $category) {
      if ($prev_category ne '') {
        print $techf "</ul>\n";
      }
      print $techf "<div class='subsection'>$category</div>\n";
      print $techf "<ul>\n";
      $prev_category = $category;
    }

    print $techf "<li><a href='$tech_id/$insn->{Attrs}->{name}.html'>$insn->{Attrs}->{name}</a></li>\n";

    open my $f, ">", $fn or die "can't open $fn for output";
    print $f "<html>\n";
    print $f "  <head>\n";
    print $f "    <title>$insn->{Attrs}->{name}</title>\n";
    print $f "    <link rel='stylesheet' type='text/css' href='../ssestyle.css'>\n";
    print $f "  </head>\n";
    print $f "  <body>\n";

    print $f "<a name='$insn->{Attrs}->{name}'></a>\n";
    print $f "<div class='intrinsic'>\n";
    print $f "<div class='name'>$insn->{Attrs}->{name}</div>\n";
    print $f "<div class='subsection'>Classification</div>\n";
    print $f "<div class='category'>\n<a href='../$tech_id.html'>$k</a>, $category, CPUID Test: ";
    if (my $cpuid = get_child $insn, 'CPUID') {
      print $f "$cpuid->{Text}";
    } else {
      print $f "None";
    }
    print $f "</div>\n";
    if (my $header = get_child $insn, 'header') {
      print $f "<div class='subsection'>Header File</div>\n";
      print $f "<div class='header'>$header->{Text}</div>\n";
    }
    if (my $i = get_child $insn, 'instruction') {
      print $f "<div class='subsection'>Instruction</div>\n";
      my $form = $i->{Attrs}->{form} || "";
      print $f "<div class='instruction'>$i->{Attrs}->{name} $form</div>\n";
    }
    print $f "<div class='subsection'>Synopsis</div>\n";
    print $f "<pre class='synopsis'>\n";
    my $rettype = $insn->{Attrs}->{rettype};
    print $f "$rettype " if defined $rettype;
    print $f "$insn->{Attrs}->{name}(";
    my @args = map { my $q = "$_->{Attrs}->{type} $_->{Attrs}->{varname}"; $q =~ s/\s+$//; $q } get_children($insn, "parameter");
    print $f join(', ',  @args);
    print $f ");</pre>\n";
    if (my $descr = get_child($insn, "description")) {
      print $f "<div class='subsection'>Description</div>\n";
      print $f "<div class='description'>$descr->{Text}</div>\n";
    }
    if (my $op = get_child($insn, "operation")) {
      my $text = utf8::encode($op->{Text});
      print $f "<div class='subsection'>Operation</div>\n";
      print $f "<pre class='operation'>\n$op->{Text}\n</pre>\n";
    }
    print $f "</div>\n";

    print $f "  </body>\n";
    print $f "</html>\n";
    close $f;
  }

  print $techf "</ul></body></html>\n";
  close $techf;
}

print $index "</ul></body></html>\n";
close $index;

print "Copy stylesheet\n";
copy("ssestyle.css", "$outdir/Contents/Resources/Documents/ssestyle.css") or die "copy failed: $!";
print "Copy Info.plist\n";
copy("Info.plist", "$outdir/Contents/Info.plist") or die "copy failed: $!";
print "Copy icon\n";
copy("icon.png", "$outdir/icon.png") or die "copy failed: $!";

print "Generating SQLite database\n";
# Generate SQLite data
do {
  open my $fh, "| sqlite3 $outdir/Contents/Resources/docSet.dsidx";
  print $fh "CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);\n";
  print $fh "CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);\n";
  while (my ($k, $v) = each %$by_tech) {
    my $tech_id = $k;
    $tech_id =~ tr/A-Za-z0-9/_/c;
    foreach my $insn (@$v) {
      my $fn = "$tech_id/$insn->{Attrs}->{name}.html";
      my $name = $insn->{Attrs}->{name};
      print $fh "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('$name', 'Function', '$fn');\n";
      if (my $i = get_child $insn, 'instruction') {
        print $fh "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('$i->{Attrs}->{name}', 'Instruction', '$fn');\n";
      }
    }
  }
  close $fh;
} if (1); # toggle here during dev to speed things up..

print "Done";

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
  my $cpuid = get_child($insn, "CPUID");
  my $tech = defined $cpuid ? $cpuid->{Text} : "Other";
  push @{$by_tech->{$tech}}, $insn;
}

print "Generating HTML\n";
# Generate HTML
while (my ($k, $v) = each %$by_tech) {
  my $tech_id = $k;
  $tech_id =~ tr/A-Za-z0-9/_/c;
  foreach my $insn (@$v) {
    my $odir = "$outdir/Contents/Resources/Documents/$tech_id";
    unless (-e $odir) { 
      make_path $odir or die "couldn't make $odir: $!";
    }
    my $fn = "$odir/$insn->{Attrs}->{name}.html";
    open my $f, ">", $fn or die "can't open $fn for output";
    print $f "<html>\n";
    print $f "  <head>\n";
    print $f "    <title>$k Intrinsics</title>\n";
    print $f "    <link rel='stylesheet' type='text/css' href='../ssestyle.css'>\n";
    print $f "  </head>\n";
    print $f "  <body>\n";

    print $f "<a name='$insn->{Attrs}->{name}'></a>\n";
    print $f "<div class='intrinsic'>\n";
    print $f "<div class='name'>$insn->{Attrs}->{name}</div>\n";
    print $f "<div class='subsection'>CPUID Feature Level</div>\n";
    print $f "<div class='cpuid'>$k</div>\n";
    if (my $category = get_child $insn, 'category') {
      print $f "<div class='subsection'>Category</div>\n";
      print $f "<div class='category'>$category->{Text}</div>\n";
    }
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
    print $f "$rettype" if defined $rettype;
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
}

print "Copy stylesheet\n";
copy("ssestyle.css", "$outdir/Contents/Resources/Documents/ssestyle.css") or die "copy failed: $!";
print "Copy Info.plist\n";
copy("Info.plist", "$outdir/Contents/Info.plist") or die "copy failed: $!";

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
      print $fh "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('$name', 'Function', '$fn#$name');\n";
      if (my $i = get_child $insn, 'instruction') {
        print $fh "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('$i->{Attrs}->{name}', 'Instruction', '$fn#$name');\n";
      }
    }
  }
  close $fh;
};

print "Done";

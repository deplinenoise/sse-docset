#! /usr/bin/env perl

use strict;
use warnings;
use XML::Parser;
use File::Copy;
use File::Path qw(make_path remove_tree);
use Template;
use utf8;

my $tt = Template->new();

my @stack;
my $result;

our $outdir = 'IntelIntrinsics.docset';
our $html_base = "$outdir/Contents/Resources/Documents";

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

print "Generating HTML\n";

# Generate HTML

sub get_category {
  my $insn = shift;
  if (my $category = get_child $insn, 'category') {
    return $category->{Text};
  }
  return "Other";
}

sub tech_id {
  my $k = shift;
  $k =~ tr/A-Za-z0-9/_/c;
  return $k;
}

# Generate index.html
do {
  my $index_data = {};

  for my $k (sort keys %$by_tech) {
    my $tech_id = tech_id $k;
    make_path "$html_base/$tech_id" unless -d "$html_base/$tech_id";
    push @{$index_data->{technologies}}, { href => "$tech_id.html", name => $k };
  }

  $tt->process('templates/index', $index_data, "$html_base/index.html");
};

# Generate technology pages
for my $tech (sort keys %$by_tech) {
  my $tech_id = tech_id $tech;
  my $cath;
  foreach my $insn (@{$by_tech->{$tech}}) {
    my $cat = get_category $insn;
    push @{$cath->{$cat}}, $insn->{Attrs}->{name};
  }

  my $cats = [];
  foreach my $cat (sort keys %$cath) {
    push @$cats, {
      name => $cat,
      insns => $cath->{$cat}
    };
  }

  my $tech_data = {
    name => $tech,
    categories => $cats,
  };
  
  $tt->process('templates/tech', $tech_data, "$html_base/$tech_id.html");
}

# Generate instruction pages.

sub get_cpuid {
  my $insn = shift;
  if (my $cpuid = get_child $insn, 'CPUID') {
    return $cpuid->{Text};
  }
  return "None";
}

sub get_header {
  my $insn = shift;
  if (my $h = get_child $insn, 'header') {
    return $h->{Text};
  }
  return "";
}

sub get_instruction {
  my $insn = shift;
  if (my $i = get_child $insn, 'instruction') {
    my $form = $i->{Attrs}->{form} || "";
    return "$i->{Attrs}->{name} $form";
  }
  return "";
}

sub get_synopsis {
  my $insn = shift;
  my $rettype = $insn->{Attrs}->{rettype} || "";
  my $result = "$rettype $insn->{Attrs}->{name}(";
  my @args = map { my $q = "$_->{Attrs}->{type} $_->{Attrs}->{varname}"; $q =~ s/\s+$//; $q } get_children($insn, "parameter");
  $result .= join(', ',  @args);
  $result .= ");";
  return $result;
}

sub get_description {
  my $insn = shift;
  if (my $descr = get_child($insn, "description")) {
    return $descr->{Text};
  }
  return "";
}

sub get_operation {
  my $insn = shift;
  if (my $op = get_child($insn, "operation")) {
    my $text = $op->{Text};
    utf8::encode $text;
    return $text;
  }
  return "";
}

for my $insn (@{$result->{Children}}) {

  my $data = {
    name        => $insn->{Attrs}->{name},
    tech_name   => $insn->{Attrs}->{tech},
    tech_id     => tech_id($insn->{Attrs}->{tech}),
    category    => get_category($insn),
    cpuid       => get_cpuid($insn),
    header      => get_header($insn),
    instruction => get_instruction($insn),
    synopsis    => get_synopsis($insn),
    description => get_description($insn),
    operation   => get_operation($insn),
  };

  $tt->process('templates/insn', $data, "$html_base/$data->{tech_id}/$data->{name}.html") || die;
}

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

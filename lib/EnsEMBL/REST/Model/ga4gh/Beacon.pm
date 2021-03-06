=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute 
Copyright [2016-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::REST::Model::ga4gh::Beacon;

use Moose;
extends 'Catalyst::Model';
use Catalyst::Exception;

use EnsEMBL::REST::Model::ga4gh::ga4gh_utils;
use Bio::EnsEMBL::Variation::Utils::Sequence qw(trim_sequences); 

use Scalar::Util qw/weaken/;
with 'Catalyst::Component::InstancePerContext';

has 'context' => (is => 'ro',  weak_ref => 1);

sub build_per_context_instance {
  my ($self, $c, @args) = @_;
  weaken($c);
  return $self->new({ context => $c, %$self, @args });
}

# TODO - Only look up assembly once

# returns ga4gh Beacon
sub get_beacon {
  my ($self) = @_;
  my $beacon;

  # The Beacon identifier depends on the assembly requested
  my $db_meta = $self->fetch_db_meta();

  my $db_assembly = $db_meta->{assembly} || '';
  my $schema_version = $db_meta->{schema_version} || '';

  my $welcomeURL = 'http://rest.ensembl.org';
  if ($db_assembly eq 'GRCh37') {
    $welcomeURL = 'http://grch37.ensembl.org';
  }

  my $altURL = 'http://www.ensembl.org';
  if ($db_assembly eq 'GRCh37') {
    $altURL = 'http://grch37.ensembl.org';
  }

  # Unique identifier of the Beacon
  $beacon->{id} = 'ensembl';
  $beacon->{name} = 'EBI - Ensembl';

  $beacon->{apiVersion} = 'v1.0.1';
  $beacon->{organization} =  $self->get_beacon_organization($db_meta);
  $beacon->{description} = 'Human variant data from the Ensembl database';
  $beacon->{version} = $schema_version;

  $beacon->{welcomeUrl} = $welcomeURL;
  $beacon->{alternativeUrl} = $altURL;
  $beacon->{createDateTime} = undef;
  $beacon->{updateDateTime} = undef;
  $beacon->{datasets} = [$self->get_beacon_dataset($db_meta)];
  $beacon->{sampleAlleleRequests} = undef;
  $beacon->{info} = undef;
  
  return $beacon;

}

# returns ga4gh BeaconOrganization
sub get_beacon_organization {
  my ($self, $db_meta) = @_;

  my $organization;
  
  my $description = "Ensembl creates, integrates and distributes reference datasets"
                    . " and analysis tools that enable genomics."
                    . " We are based at EMBL-EBI and our software"
                    . " and data are freely available.";

  my $address = "EMBL-EBI, Wellcome Genome Campus, Hinxton, "
                . "Cambridgeshire, CB10 1SD, UK";

  # The welcome URL depends on the assembly requested
  #my $db_assembly = $db_meta->{assembly};

  #my $welcomeURL = "http://www.ensembl.org";
  #if ($db_assembly eq 'GRCh37') {
  #  $welcomeURL = "http://grch37.ensembl.org";
  #}
  
  my $welcomeURL = "https://www.ebi.ac.uk/";
  my $contactURL = "http://www.ensembl.org/info/about/contact/index.html";
  
# TODO add URL to logo
  my $logoURL; 

  # Unique identifier of the organization
  $organization->{id} = "ebi-ensembl";
  $organization->{name} = "EMBL European Bioinformatics Institute";
  $organization->{description} = $description;
  $organization->{address} = $address;
  $organization->{welcomeUrl} = $welcomeURL;
  $organization->{contactUrl} = $contactURL;
  $organization->{logoUrl} = $logoURL;
  $organization->{info} = undef;
  return $organization;
}

sub get_beacon_dataset {
  my ($self, $db_meta) = @_;

  my $dataset;
  
  my $db_assembly = $db_meta->{assembly};
  my $schema_version = $db_meta->{schema_version};
  my $externalURL = 'http://www.ensembl.org';
  if ($db_assembly eq 'GRCh37') {
    $externalURL = 'http://grch37.ensembl.org';
  }

  $dataset->{id} = join(" ", 'Ensembl', $schema_version);
  $dataset->{name} = join(" ", 'Ensembl', $schema_version);
  $dataset->{description} = "Human variant data from the Ensembl database";
  $dataset->{assemblyId} = $db_assembly;
  $dataset->{createDateTime} = undef;
  $dataset->{updateDateTime} = undef;
  $dataset->{version} = $schema_version;
  $dataset->{variantCount} = undef;
  $dataset->{callCount} = undef;
  $dataset->{sampleCount} =  undef;
  $dataset->{externalUrl} = $externalURL; 
  $dataset->{info} = undef;
  return $dataset;
}

sub beacon_query {
 
  my ($self, $data) = @_;
  my $beaconAlleleResponse;
  my $beaconError;

  my $beacon = $self->get_beacon();
 
  $beaconError = $self->check_parameters($data); 

  my $beaconAlleleRequest = $self->get_beacon_allele_request($data);
  
  my $incl_ds_response = 0;
  if (exists $data->{includeDatasetResponses}) {
    if ($data->{includeDatasetResponses} eq 'ALL') {
	$incl_ds_response = 1;
    } elsif ($data->{includeDatasetResponses} eq 'NONE') {
        $incl_ds_response = 0;
    }
  }

  $beaconAlleleResponse->{beaconId} = $beacon->{id};
  $beaconAlleleResponse->{exists} = undef;
  $beaconAlleleResponse->{error} = $beaconError;
  $beaconAlleleResponse->{alleleRequest} = $beaconAlleleRequest;
  $beaconAlleleResponse->{datasetAlleleResponses} = undef;

  # Check assembly requested is assembly of DB
  my $db_meta = $self->fetch_db_meta();
  my $db_assembly = $db_meta->{'assembly'};
  
  my $assemblyId = $data->{assemblyId};
  if (uc($db_assembly) ne uc($assemblyId)) {
      $beaconError = $self->get_beacon_error(400, "User provided assemblyId (" .
                                                  $assemblyId . ") does not match with dataset assembly (" . $db_assembly . ")");
      $beaconAlleleResponse->{error} = $beaconError;
      return $beaconAlleleResponse;
  }
 
  # check variant if only all parameters are valid
  if(!defined($beaconError)){ 
    # Check allele exists 
    my $reference_name = $data->{referenceName};
    my $start = $data->{start};
    my $end = $data->{end} ? $data->{end} : $data->{start}; 
    my $ref_allele = $data->{referenceBases};
    my $alt_allele = $data->{alternateBases} ? $data->{alternateBases} : $data->{variantType};

    # Currently assumes only 1 dataset
    # TODO Multiple dataset - for each dataset
    # check variant exists and report exists overall
    #
    my $dataset = $self->get_beacon_dataset($db_meta);

    my ($exists, $dataset_response)  = $self->variant_exists($reference_name,
                                       $start,
                                       $end,
                                       $ref_allele,
                                       $alt_allele,
                                       $incl_ds_response, $dataset);

    my $exists_JSON = $exists;
    if ($exists) {
      $exists_JSON = JSON::true;
    } else {
      $exists_JSON = JSON::false;
    }
    $beaconAlleleResponse->{exists} = $exists_JSON;
    if ($incl_ds_response) {
      $beaconAlleleResponse->{datasetAlleleResponses} = [$dataset_response];
    }
  }
  return $beaconAlleleResponse;				
  
}

sub check_parameters {
  my ($self, $parameters) = @_;
  my $error = undef;

  my @required_fields = qw/referenceName start referenceBases assemblyId/;

  if($parameters->{'alternateBases'}){
    push(@required_fields, 'alternateBases');
  }
  elsif($parameters->{'variantType'}){
    push(@required_fields, 'variantType');
    push(@required_fields, 'end');
  }

  foreach my $key (@required_fields) {
    return $self->get_beacon_error('400', "Missing mandatory parameter $key")
      unless (exists $parameters->{$key});
  }

  my @optional_fields = qw/content-type callback datasetIds includeDatasetResponses/;

  my %allowed_fields = map { $_ => 1 } @required_fields,  @optional_fields;

  for my $key (keys %$parameters) {
    return $self->get_beacon_error('400', "Invalid parameter $key")
      unless (exists $allowed_fields{$key});
  }

  # Note: Does not 
  #   allow a * that is VCF spec for ALT
  if($parameters->{referenceName} !~ /^([1-9]|1[0-9]|2[012]|X|Y|MT)$/i){
    $error = $self->get_beacon_error('400', "Invalid referenceName");
  }
  elsif($parameters->{start} !~ /^\d+$/){
    $error = $self->get_beacon_error('400', "Invalid start");
  }
  elsif(defined($parameters->{end}) && $parameters->{end} !~ /^\d+$/){
    $error = $self->get_beacon_error('400', "Invalid end");
  }
  elsif($parameters->{referenceBases} !~ /^[AGCTN]+$/i){
    $error = $self->get_beacon_error('400', "Invalid referenceBases");
  }
  elsif(defined($parameters->{alternateBases}) && $parameters->{alternateBases} !~ /^[AGCTN]+$/i){
    $error = $self->get_beacon_error('400', "Invalid alternateBases");
  }
  elsif(defined($parameters->{variantType}) && $parameters->{variantType} !~ /^(DEL|INS|CNV|DUP|INV|DUP\:TANDEM)$/i){
    $error = $self->get_beacon_error('400', "Invalid variantType");
  }
  elsif($parameters->{assemblyId} !~ /^(GRCh38|GRCh37)$/i){
    $error = $self->get_beacon_error('400', "Invalid assemblyId");
  }

  return $error; 
   
}

# Get beacon_allele_request
sub get_beacon_allele_request {
  my ($self, $data) = @_;
  my $beaconAlleleRequest;

  for my $field (qw/referenceName start referenceBases alternateBases variantType end assemblyId/) {
      $beaconAlleleRequest->{$field} = $data->{$field};
  }
  $beaconAlleleRequest->{datasetIds} = undef;

  $beaconAlleleRequest->{includeDatasetResponses} = undef;
  if (exists $data->{includeDatasetResponses}) {
    if ($data->{includeDatasetResponses} eq 'ALL') {
  	$beaconAlleleRequest->{includeDatasetResponses} = JSON::true;
    } elsif ($data->{includeDatasetResponses} eq 'NONE') {
  	$beaconAlleleRequest->{includeDatasetResponses} = JSON::false;
    }
  }
  return $beaconAlleleRequest;
}

sub get_beacon_error {
  my ($self, $error_code, $message) = @_;
 
  my $error = {
                "errorCode"    => $error_code,
                "errorMessage" => $message,
              };
  return $error;
}

sub get_assembly {
  my ($self) = @_;
  my $db_meta = $self->fetch_db_meta();
  return $db_meta->{assembly};
}

# Fetch required meta info 
# TODO place in utilities
sub fetch_db_meta {
  my ($self)  = @_;

  # my $c = $self->context();-
  # $c->log()->info("for info");
  my $species = 'homo_sapiens';
  my $core_ad = $self->context->model('Registry')->get_DBAdaptor($species, 'Core');

  ## extract required meta data from core db
  my $cmeta_ext_sth = $core_ad->dbc->db_handle->prepare(qq[ select meta_key, meta_value from meta]);
  $cmeta_ext_sth->execute();
  my $core_meta = $cmeta_ext_sth->fetchall_arrayref();

  my %cmeta;
  foreach my $l(@{$core_meta}){
    $cmeta{$l->[0]} = $l->[1];
  }

  ## default ensembl set names/ids
  my $db_meta;
  $db_meta->{datasetId}      = "Ensembl";
  $db_meta->{id}             = join(".", "Ensembl",
                                         $cmeta{"schema_version"},
                                         $cmeta{"assembly.default"});
  $db_meta->{assembly}       = $cmeta{"assembly.default"};
  $db_meta->{schema_version} = $cmeta{"schema_version"};
 
  return $db_meta;
}

# TODO  parameter for species
# TODO  use assemblyID
# Assembly not taken to account, assembly of REST machine
# TODO Report by individul datasets - only 1 currently
sub variant_exists {
  my ($self, $reference_name, $start, $end, $ref_allele, 
           $alt_allele, $incl_ds_response, $dataset) = @_;

  my $c = $self->context();
 
  my $sv = 0;  
  my $found = 0;
  my $vf_found;
  my $error;
  my $dataset_response;

  my $slice_step = 5;

  # Position provided is zero-based
  my $start_pos  = $start + 1; 
  my $end_pos  = $end + 1; 
  my $chromosome = $reference_name;

  # Reference bases for this variant (starting from start). 
  # Accepted values: see the REF field in VCF 4.2 specification 
  # (http://samtools.github.io/hts-specs/VCFv4.2.pdf)

  my ($new_ref, $new_alt, $new_start, $new_end, $changed) =
        @{trim_sequences($ref_allele, $alt_allele, $start_pos, $end_pos, 1)};

  my $slice_start = $start_pos - $slice_step;
  my $slice_end   = $end_pos + $slice_step;

  my $slice_adaptor = $c->model('Registry')->get_adaptor('homo_sapiens', 'core', 'slice');
  my $slice = $slice_adaptor->fetch_by_region('chromosome', $chromosome, $slice_start, $slice_end);

  my $variation_feature_adaptor; 

  if($alt_allele =~ /DEL|INS|CNV|DUP|INV|DUP:TANDEM/){
    $sv = 1; 
  }

  if($sv == 1){
    $variation_feature_adaptor = $c->model('Registry')->get_adaptor('homo_sapiens', 'variation', 'StructuralVariationFeature'); 
  }
  else{
    $variation_feature_adaptor = $c->model('Registry')->get_adaptor('homo_sapiens', 'variation', 'variationFeature');
  }
  my $variation_features  = $variation_feature_adaptor->fetch_all_by_Slice($slice);

  if (! scalar(@$variation_features)) {
    return (0);
  }

  my ($seq_region_name, $seq_region_start, $seq_region_end, $strand);
  my ($allele_string);
  my ($ref_allele_string, $alt_alleles);
  my ($so_term); 

  foreach my $vf (@$variation_features) {
    $seq_region_name = $vf->seq_region_name();
    $seq_region_start = $vf->seq_region_start();
    $seq_region_end = $vf->seq_region_end();
    $allele_string = $vf->allele_string();
    $strand = $vf->strand();

    if ($strand != 1) {
        next;
    }

    # Precise match for all types of variants 
    if (($seq_region_start != $new_start) && ($seq_region_end != $new_end)) {
        next;
    }

    # Variant is a SNV
    if ($sv == 0) {
    $ref_allele_string = $vf->ref_allele_string();
    $alt_alleles = $vf->alt_alleles();

    if ((uc($ref_allele_string) eq uc($new_ref))
      && (grep(/^$new_alt$/i, @{$alt_alleles}))) {
        $found = 1;
        if ($incl_ds_response) {
          $vf_found = $vf;
        }
        last;
      } else {
          $found = 0;
      }
    }
    # Variant is a SV 
    else {
      # convert to SO term 
      my %terms = (
        INS  => 'insertion',
        DEL  => 'deletion',
        CNV  => 'copy_number_variation',
        DUP  => 'duplication',
        INV  => 'inversion',
        'DUP:TANDEM' => 'tandem_duplication'
      );

      my $vf_so_term;
      $so_term = defined $terms{$alt_allele} ? $terms{$alt_allele} : $alt_allele;
      $vf_so_term = $vf->class_SO_term();

      if ($vf_so_term eq $so_term) {
        $found = 1;
        if ($incl_ds_response) {
          $vf_found = $vf;
        }
        last;
      } else {
        $found = 0;
      }
    }
  }

  if ($incl_ds_response) {
    $dataset_response = get_dataset_allele_response($dataset, $found, $vf_found, $error);
  }
  return ($found, $dataset_response);
}

# Returns a BeaconDatasetAlleleResponse for a
# variant feature
# Assumes that it exists
sub get_dataset_allele_response {
  my ($dataset, $found, $vf, $error) = @_;
 
  my $ds_response;

  $ds_response->{'datasetId'} = $dataset->{id};
  $ds_response->{'exists'} = undef;
  $ds_response->{'error'} = undef;
  $ds_response->{'frequency'} = undef
  $ds_response->{'variantCount'} = undef;
  $ds_response->{'callCount'} = undef;
  $ds_response->{'sampleCount'} = undef;
  $ds_response->{'note'} = undef;
  $ds_response->{'externalUrl'} = undef;
  $ds_response->{'info'} = undef;

  if (! defined $found) {
    $ds_response->{'error'} = $error;
    return $ds_response;
  }
  if (! $found) {
    $ds_response->{'exists'} = JSON::false;
    return $ds_response;
  }
 
  $ds_response->{'exists'} = JSON::true;
 
  my $externalURL = "http://www.ensembl.org";
  if ($dataset->{assemblyId} eq 'GRCh37') {
    $externalURL = "http://grch37.ensembl.org";
  }
  $externalURL .= "/Homo_sapiens/Variation/Explore?v=" . $vf->name();
  $ds_response->{'externalUrl'} = $externalURL;
  return $ds_response;
}

with 'EnsEMBL::REST::Role::Content';

__PACKAGE__->meta->make_immutable;

1;

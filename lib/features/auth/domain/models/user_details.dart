class UserDetails {
  const UserDetails({
    this.name,
    this.gender,
    this.address,
    this.mobileNumber,
    this.user,
    this.fullName,
    this.created,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.owner,
    this.docstatus,
    this.idx,
  });

  factory UserDetails.fromJson(Map<String, dynamic> json) {
    return UserDetails(
      name: json['name'] as String?,
      gender: json['gender'] as String?,
      address: json['address'] as String?,
      mobileNumber: json['mobile_number'] as String?,
      user: json['user'] as String?,
      fullName: json['full_name'] as String?,
      created: json['created'] as String?,
      creation: json['creation'] as String?,
      modified: json['modified'] as String?,
      modifiedBy: json['modified_by'] as String?,
      owner: json['owner'] as String?,
      docstatus: json['docstatus'] as int?,
      idx: json['idx'] as int?,
    );
  }

  final String? name;
  final String? gender;
  final String? address;
  final String? mobileNumber;
  final String? user;
  final String? fullName;
  final String? created;
  final String? creation;
  final String? modified;
  final String? modifiedBy;
  final String? owner;
  final int? docstatus;
  final int? idx;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gender': gender,
      'address': address,
      'mobile_number': mobileNumber,
      'user': user,
      'full_name': fullName,
      'created': created,
      'creation': creation,
      'modified': modified,
      'modified_by': modifiedBy,
      'owner': owner,
      'docstatus': docstatus,
      'idx': idx,
    };
  }
}

// Run with the production PublishValidation enum (Foundation, no UI/network required).
let cases: [(Bool, Bool, String, [PublishValidation.RequiredField])] = [
    (false, false, "", [.photo, .title]),
    (false, false, "街头光影", [.photo]),
    (true, false, "", [.title]),
    (true, false, " \n\t　", [.title]),
    (true, false, " 街头光影 ", []),
    (false, true, "", [.photo]),
    (true, true, "", []),
    (true, false, "编辑后的作品", [])
]
for (hasPhoto, isAssignment, title, expected) in cases {
    precondition(PublishValidation.missingFields(hasPhoto: hasPhoto, isAssignment: isAssignment, title: title) == expected)
}
precondition(PublishValidation.RequiredField.photo.reminder == "请选择一张照片")
precondition(PublishValidation.RequiredField.title.reminder == "请填写作品标题")
print("PASS: 8 publish validation cases and 2 required-field reminders")

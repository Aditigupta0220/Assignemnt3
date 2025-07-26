import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final dbRef = FirebaseDatabase.instance.ref();
  int _selectedIndex = 0;
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  File? selectedImage;

  final String cloudName = "dgp3m1fei";
  final String uploadPreset = "rishu__2107";

  Future<void> uploadImage(File file) async {
    try {
      final uploadUrl = "https://api.cloudinary.com/v1_1/$cloudName/image/upload";

      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();

      if (response.statusCode == 200) {
        final resStr = await response.stream.bytesToString();
        final imageUrl = jsonDecode(resStr)['secure_url'];
        await dbRef.child("users/${user!.uid}/profileImage").set(imageUrl);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Profile image updated!")),
        );
      } else {
        final errorText = await response.stream.bytesToString();
        print("Upload failed: $errorText");
      }
    } catch (e) {
      print("Exception during image upload: $e");
    }
  }

  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      await uploadImage(File(picked.path));
    }
  }

  Future<void> updateProfile(String name, String email) async {
    await dbRef.child("users/${user!.uid}/name").set(name);
    await dbRef.child("users/${user!.uid}/email").set(email);
  }

  Future<void> addPost(String text, File? imageFile) async {
    String? imageUrl;
    if (imageFile != null) {
      try {
        final uploadUrl = "https://api.cloudinary.com/v1_1/$cloudName/image/upload";

        final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
          ..fields['upload_preset'] = uploadPreset
          ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

        final response = await request.send();

        if (response.statusCode == 200) {
          final resStr = await response.stream.bytesToString();
          final resData = jsonDecode(resStr);
          imageUrl = resData['secure_url'];
        } else {
          final errorText = await response.stream.bytesToString();
          print("Post image upload failed: $errorText");
        }
      } catch (e) {
        print("Post upload error: $e");
      }
    }

    final postRef = dbRef.child("posts").push();
    await postRef.set({
      'uid': user!.uid,
      'text': text,
      'image': imageUrl ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Widget buildProfileTab(Map userMap) {
    nameController.text = userMap['name'];
    emailController.text = userMap['email'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: GestureDetector(
              onTap: pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: (userMap['profileImage'] ?? '').isNotEmpty
                    ? NetworkImage(userMap['profileImage'])
                    : null,
                child: (userMap['profileImage'] ?? '').isEmpty
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name")),
          TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email")),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => updateProfile(nameController.text, emailController.text),
            child: const Text("Update Profile"),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text("My Posts", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          buildMyPostsTab()
        ],
      ),
    );
  }

  Widget buildMyPostsTab() {
    return StreamBuilder(
      stream: dbRef.child("posts").orderByChild("uid").equalTo(user!.uid).onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const CircularProgressIndicator();
        final data = (snapshot.data! as DatabaseEvent).snapshot.value;
        if (data == null) return const Text("No posts yet");
        final Map posts = data as Map;
        final items = posts.values.toList();
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final post = items[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text(post['text'] ?? ''),
                subtitle: Text(post['timestamp'].toString()),
                leading: post['image'] != ''
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(post['image'], width: 60, height: 60, fit: BoxFit.cover),
                )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Widget buildAllPostsTab() {
    return StreamBuilder(
      stream: dbRef.child("posts").onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const CircularProgressIndicator();
        final data = (snapshot.data! as DatabaseEvent).snapshot.value;
        if (data == null) return const Text("No posts available");
        final Map posts = data as Map;
        final items = posts.values.toList();
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final post = items[index];
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text(post['text'] ?? ''),
                subtitle: Text(post['timestamp'].toString()),
                leading: post['image'] != ''
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(post['image'], width: 60, height: 60, fit: BoxFit.cover),
                )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Widget buildAddPostTab() {
    final TextEditingController postController = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          children: [
            TextField(controller: postController, decoration: const InputDecoration(labelText: "Write something")),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() {
                    selectedImage = File(picked.path);
                  });
                }
              },
              child: const Text("Select Image (optional)"),
            ),
            const SizedBox(height: 10),
            if (selectedImage != null) Image.file(selectedImage!, width: 100, height: 100),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await addPost(postController.text.trim(), selectedImage);
                postController.clear();
                setState(() {
                  selectedImage = null;
                });
              },
              child: const Text("Post"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [
      StreamBuilder(
        stream: dbRef.child("users/${user!.uid}").onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null) return const CircularProgressIndicator();
          final userMap = (snapshot.data! as DatabaseEvent).snapshot.value as Map;
          return buildProfileTab(userMap);
        },
      ),
      buildAllPostsTab(),
      buildAddPostTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile App"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: "All Posts"),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: "Add Post"),
        ],
      ),
    );
  }
}

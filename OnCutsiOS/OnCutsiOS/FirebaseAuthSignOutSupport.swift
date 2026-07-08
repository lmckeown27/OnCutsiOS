//
//  FirebaseAuthSignOutSupport.swift
//  OnCuts
//
//  Clears Firebase Auth when logging out (avoids “ghost” sessions alongside Google Sign-In).
//

import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

enum FirebaseAuthSignOutSupport {
    static func signOut() {
        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
        } catch {
            ProductionLogging.recordNonFatal(error, context: ["area": "firebase_auth_sign_out"])
        }
        #endif
    }
}

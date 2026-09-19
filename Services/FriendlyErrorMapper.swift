import Foundation
import CoreData

// MARK: - FriendlyErrorMapper
//
// Closes the gap surfaced in gap #1 + #6 of the Ian Lackey
// "7 Security Holes" article: raw `error.localizedDescription` leaks
// to UI can include file paths, host names, Postgres column names,
// or worse (stack-trace hints in some Cocoa errors).
//
// Every call site that previously did:
//
//     errorMessage = error.localizedDescription
//
// should now do:
//
//     errorMessage = FriendlyErrorMapper.message(for: error, in: .network | .auth | .upload)
//
// The mapper recognises URLError, NSError with Cocoa/Foundation
// domains, AuthService.AuthError, and falls back to a generic
// "Something went wrong. Please try again." for everything else.
//
// NEVER pre-trust `error.localizedDescription` for user-facing copy.

enum FriendlyErrorMapper {

    // MARK: - Context

    enum Context {
        case network
        case auth
        case upload
        case purchase
        case aiGeneration
        case settings

        var defaultMessage: String {
            switch self {
            case .network:
                return "No connection. Check your internet and try again."
            case .auth:
                return "Something went wrong. Try again in a moment."
            case .upload:
                return "Couldn't process that file. Make sure it's a valid PDF, photo, or text."
            case .purchase:
                return "Couldn't complete that purchase right now. Please try again."
            case .aiGeneration:
                return "AI generation hit a snag. Try again in a moment, or upgrade for priority."
            case .settings:
                return "Couldn't save that setting. Please try again."
            }
        }
    }

    // MARK: - Entry point

    static func message(for error: Error, in context: Context) -> String {
        if let authError = error as? AuthService.AuthError,
           let desc = authError.errorDescription {
            return desc
        }

        let nsError = error as NSError

        if nsError.code == -34018 {
            return "Storage permissions changed. Please reinstall VerbaDoc."
        }

        if nsError.domain == NSURLErrorDomain {
            return mapURLError(code: nsError.code, context: context)
        }

        if nsError.domain == NSCocoaErrorDomain {
            return mapCocoaError(code: nsError.code, context: context)
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return mapPOSIXError(code: nsError.code, context: context)
        }

        return context.defaultMessage
    }

    // MARK: - NSCocoaErrorCode curated map
    //
    // Raw Int literals used instead of NSCocoaError.Code.*.rawValue —
    // these are stable, documented Apple constants (see Foundation's
    // FoundationErrors.h / CoreData's CoreDataErrors.h).
    private static func mapCocoaError(code: Int, context: Context) -> String {
        switch code {
        // Save-time failures
        case 134030, // persistentStoreSaveError
             134130: // persistentStoreOutOfDateError
            return "Couldn't save your changes right now. Please try again."

        // Open-time failures
        case 134020, // persistentStoreOpenError
             134100, // persistentStoreIncompatibleVersionHashError
             134140: // persistentStoreIncompatibleSchemaError
            return "Couldn't open local storage. Please reinstall VerbaDoc."

        case 134050: // persistentStoreSaveConflictsError
            return "You have unsaved changes from another screen. Please reload and try again."

        // Domain validation — deliberately fall through to default message
        case 1560, // validationMultipleErrorsError
             1570, // validationMissingMandatoryPropertyError
             1660, // validationStringPatternMatchingError
             1620, // validationStringTooLongError
             1640, // validationNumberTooLargeError
             1650: // validationNumberTooSmallError
            return context.defaultMessage

        // File I/O
        case 260: // fileReadNoSuchFileError
            return "Couldn't find that file on your device."
        case 259, // fileReadCorruptFileError
             261:  // fileReadUnsupportedSchemeError
            return "That file looks damaged. Try a different one."
        case 513, // fileWriteNoPermissionError
             640:  // fileWriteOutOfSpaceError
            return "Couldn't save that file. Free up some storage and try again."

        default:
            return context.defaultMessage
        }
    }

    // MARK: - NSPOSIXErrorCode curated map
    private static func mapPOSIXError(code: Int, context: Context) -> String {
        switch code {
        case 1:  // EPERM
            return "Your device blocked that operation. Please try again."
        case 2:  // ENOENT
            return "Couldn't find that file."
        case 28: // EAGAIN
            return "That took too long. Please try again."
        case 30: // EROFS
            return "Your device storage is locked. Please unlock and try again."
        case 63, 64:  // ENETUNREACH / ENETDOWN
            return context.defaultMessage
        default:
            return context.defaultMessage
        }
    }

    // MARK: - URLError mapping

    private static func mapURLError(code: Int, context: Context) -> String {
        switch code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed:
            return "No connection. Check your internet and try again."

        case NSURLErrorTimedOut:
            return "That took too long. Try again in a moment, or check your connection."

        case NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed:
            return "Couldn't reach the server. Check your connection and try again."

        case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
            return "That link doesn't look right. Double-check and try again."

        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return "Secure connection failed. Please try again on a trusted network."

        case NSURLErrorCancelled:
            return "Cancelled."

        default:
            return context.defaultMessage
        }
    }
}
